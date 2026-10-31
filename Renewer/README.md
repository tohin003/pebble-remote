# Pebble Remote Renewer

A small Mac menu-bar item that keeps Pebble Remote signed. Pebble Remote is signed with a free Apple ID, so each
install works for 7 days. The item shows the days left and renews the app on the iPhone: when you choose Renew Now,
and by itself. It starts at every login. It is the person's request of 2026-10-30 14:49 (bridge file §7), built by
lane M (`docs/lanes/M-brief.md`).

## What it does

**In the menu bar:** the days left, such as "5 days". It shows "Expired" after the end date, "Renewing…" while a
renewal runs, and "No date" when it can't find one.

**In the menu:**

| Line | Example |
|---|---|
| The end date | "Expires Fri 6 Nov at 02:07" |
| Where the date came from, only before renew.sh has installed once | "Date from Xcode's newest profile" |
| What happens next | "Renews in 4 days", "Renews right after it expires", "Renews when your iPhone is reachable", "Renews when Pebble's timed work is done" |
| **Renew Now** | Renews right away (it still checks the HOLD and the iPhone first) |
| **Renew Automatically** | A check mark, on by default |
| The last result | "Renewed today at 09:14", or "Couldn't renew today at 09:14" and why: "Your iPhone wasn't reachable. Connect it, then choose Renew Now." |
| **Quit** | It starts again at the next login |

**Where the date comes from:**
- The build last installed. After every successful install, `scripts/renew.sh` writes an owner-only state file,
  `~/Library/Application Support/PebbleRemoteRenewer/state.json`. It holds the commit, the device, and the profile's
  dates and app id. Nothing else of the profile is kept.
- Until renew.sh has installed once, the date comes from the newest Xcode profile for `io.github.tohin003.PebbleRemote`.
  Only that profile's dates and app id are read. Profiles are read straight from their files; the Keychain and the
  `security` tool are never used for this.

**Automatic renewal.** It checks at login, on wake (a minute after) and every 30 minutes. It also checks just after the
start of the last day and just after the end date. It renews only when all of these hold:
1. 1 day or less is left, or the build has expired.
2. No Pebble HOLD is up: `scripts/hold-status.sh` exits 0. It never passes `--force`.
3. The iPhone is reachable: `xcrun devicectl list devices` shows it paired and connected, by cable or on the network.
   The iPhone renew.sh last installed on is the one used. Another iPhone never takes its place.

When 1 day or less is left and the iPhone stays out of reach for 20 minutes (twice in a row), it posts **one** Mac
notification for that end date. The notification says what to do: unlock the iPhone on the same Wi-Fi as this Mac, or
connect it with a cable. An automatic renewal that fails for a reason you can fix, such as Xcode's sign-in, also posts
one notification per end date.

**What it builds:** the commit last installed (from `state.json`), in a clean worktree, never in a working tree. A
half-done change in the repository then never reaches the iPhone.
- The worktree is `~/Library/Application Support/PebbleRemoteRenewer/worktree`. It is a `git worktree` of this
  repository, not in `/tmp` (a restart wipes `/tmp`). With its build folder it takes about 300 MB.
- Before each build it moves to the commit, drops local changes and untracked files, and keeps `build/` so later
  builds are incremental.
- Builds use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, `nice -n 19` and `xcodebuild -jobs 2`.
- It runs `scripts/renew.sh --commit <commit> --device <iPhone>`. You can run the same by hand. Two renewals never
  share the worktree: renew.sh holds `worktree.lock`, and only one copy of the item runs at a time.
- A renewal is stopped after 40 minutes.
- After a failed automatic try, it rests 25 minutes, then twice as long after each further failure in a row, up to
  6 hours. A lasting problem therefore never means a heavy build every half hour.

**The switch (brief, item 5).** Xcode may reuse a cached profile that is still valid. If it does, renewing early
doesn't move the end date. The switch is `RenewalSwitch.timing` in `Sources/RenewerCore/Policy.swift`:
- `.beforeExpiry` (now): renews once 1 day or less is left.
- `.afterExpiry`: renews right after the end date, and the menu says "Renews right after it expires". The app on the
  iPhone stops opening from the end date until the renewal finishes, usually a few minutes.

Even with `.beforeExpiry`, a renewal that leaves the date where it was makes the item wait for that end date. The menu
then says "Renewed today at 09:14; the end date didn't move" and "Renews right after it expires".

## Files

| Path | What |
|---|---|
| `Package.swift` | Its own Swift package (macOS 26, Swift 6). The iOS package, the app target and `UIAudit/` don't see it. |
| `Sources/RenewerCore/` | Everything that decides, as plain values: days left and the menu's words (`Words.swift`, `Copy.swift`), the decision to renew (`Policy.swift`), devicectl's list (`Devices.swift`), renew.sh's output and exit codes (`RenewScript.swift`), the state file (`InstallState.swift`), the renewer's record (`RenewerRecord.swift`), profiles' dates (`Profiles.swift`), the log and its redaction (`LogFile.swift`, `Redaction.swift`, `LogWords.swift`) |
| `Sources/PebbleRemoteRenewer/` | The app: SwiftUI `MenuBarExtra` (`RenewerApp.swift`), the model that schedules and acts (`RenewerModel.swift`), subprocesses (`Runner.swift`), notifications (`Notifier.swift`), `--check` (`CheckCommand.swift`), the entry point and single-copy lock (`Entry.swift`) |
| `Tests/RenewerCoreTests/` | Swift Testing tests for every part of RenewerCore |
| `Support/Info.plist` | The app bundle's Info.plist (`LSUIElement`: no Dock icon). install.sh adds the repository's path. |
| `Support/LaunchAgent.plist` | The login agent's template. install.sh fills in the app's path. |
| `install.sh`, `uninstall.sh` | Put it in place and take it away (both have `--dry-run`) |
| `../scripts/renew.sh` | Builds and installs on the iPhone. It also writes `state.json` and has `--commit` (lane M's additions). |

Once installed, it uses these places:

| Path | What |
|---|---|
| `~/Library/Application Support/PebbleRemoteRenewer/` (0700) | `Pebble Remote Renewer.app`; `state.json` (written by renew.sh); `renewer.json` (the item's own record: Renew Automatically, the last result, notices posted); `renewer.lock`; `worktree/` |
| `~/Library/LaunchAgents/io.github.tohin003.PebbleRemoteRenewer.plist` | Starts it at login. It is started again after a crash, but not after Quit. |
| `~/Library/Logs/PebbleRemoteRenewer.log` (0600) | One line per event. Over 1 MB it becomes `.log.1`. |

## Install and uninstall

Run these outside a Pebble HOLD (`scripts/hold-status.sh` says "no Pebble HOLD"), after the person has seen the item
(it builds on its own once installed):

```
scripts/swift.sh test --package-path Renewer
scripts/swift.sh build --package-path Renewer -c release --product PebbleRemoteRenewer
Renewer/install.sh --dry-run     # what it will do
Renewer/install.sh
```

- install.sh builds nothing. It puts the app in place, signed ad hoc (no identity, no Keychain), and writes the login
  agent. Then it loads the agent, which starts the item.
- The first time, macOS asks whether it may send notifications: allow them. System Settings › General › Login Items
  lists it under "Allow in the Background".
- To update, build again and run install.sh again. Don't reinstall while the bar says "Renewing…": that stops the
  build.

**Before it can renew,** renew.sh must have installed once since it started recording, so the item knows which commit
is on the iPhone. Use, with the iPhone connected:

```
scripts/renew.sh --commit <the commit to put on the iPhone>
```

From then on, install through renew.sh (`--commit`, or from a clean tree). An install by other means (Xcode's Run
button, a bare xcodebuild) doesn't update `state.json`. The item would then renew the build recorded before.

**Uninstall:**

```
Renewer/uninstall.sh             # stops it; removes the login agent and the app
Renewer/uninstall.sh --all       # also the clean worktree (git worktree remove), state.json, renewer.json, the log
```

## What it never does

- It never builds or renews during a Pebble HOLD, and never passes `--force`.
- It never builds a working tree: only the recorded commit, in its own clean worktree.
- It never changes anything on the iPhone except installing Pebble Remote through renew.sh. To find the iPhone it
  only lists devices (`devicectl list devices`).
- It never reads or changes the Keychain, signing certificates, `~/.pebble/` or Apple ID details. It never removes or
  edits provisioning profiles; it reads only their dates and app id.
- It never logs tokens, team ids, Apple ID e-mail addresses, the names in signing identities, or Personal Team
  names. Every log line is redacted first (`Redaction.swift`). Devices appear only by identifier.
- It never touches `bridge-mock/`, the test bridge on port 7443, or `UIAudit/`.
- It never runs when nobody is logged in, and never wakes the Mac. A renewal due while the Mac sleeps runs a minute
  after it wakes.
- It never runs twice at once.

## How to check it

- **What it sees and would do now,** without renewing or writing anything. It runs hold-status.sh and the device list.

  ```
  "$HOME/Library/Application Support/PebbleRemoteRenewer/Pebble Remote Renewer.app/Contents/MacOS/PebbleRemoteRenewer" --check
  ```

  It prints the repository, the installed build, the end date and where it came from, the switch, the stage, the
  HOLD, the iPhone (reachable by cable or on the network, or not), the decision, and the bar and menu words.
  Before installing, `Renewer/.build/release/PebbleRemoteRenewer --check` does the same.
- **Running:** `launchctl print gui/$(id -u)/io.github.tohin003.PebbleRemoteRenewer | head -20` (look for
  `state = running`).
- **The log:** `tail -30 ~/Library/Logs/PebbleRemoteRenewer.log`. A check's line is written only when it changes.
- **The state:** `cat ~/Library/Application\ Support/PebbleRemoteRenewer/state.json`.
- **Item 5, once, with the real iPhone (before the end date):** choose Renew Now. If the menu then says "Renewed …;
  the end date didn't move", Xcode reused its cached profile. Set `RenewalSwitch.timing = .afterExpiry`, then build,
  test and install again. If the date moved by about 7 days, keep `.beforeExpiry`.
- **Words:** `python3 -I scripts/lint_copy.py Renewer/Sources`.
