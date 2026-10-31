# Pebble Remote

Pebble Remote is an iPhone app that controls [Pebble](https://github.com/tohin003/Pebble) on your Mac: its chats,
runs, approvals and settings. It talks to Pebble directly, over your Wi-Fi at home or over Tailscale when you are away.
It works with Pebble 2.0 or later.

This repository is the app's source code. The app is not on the App Store: you build it with Xcode and install it on
your own iPhone.

## What you need

- A Mac with Xcode 26 or later. The project uses Swift 6.2 and the iOS 26 SDK. It was built and tested with Xcode 27.1.
- An iPhone on iOS 26 or later, with Face ID (or Touch ID) set up. Approvals are signed by a key that needs it.
- Pebble 2.0 or later on the Mac. Older versions have no connection for the phone.
- An Apple ID signed in to Xcode. A free one works, but its builds stop opening after 7 days (see below).
- Optional: [Tailscale](https://tailscale.com) on the Mac and the iPhone, to use the app away from home.
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46, only if you change `project.yml`.

## Build and install

1. Copy `App/Local.xcconfig.example` to `App/Local.xcconfig`. Git ignores that file. In it, set:
   - `DEVELOPMENT_TEAM` to your team's ID. Xcode shows it in Settings › Accounts.
   - `BUNDLE_ID_PREFIX` to a reverse-DNS prefix of your own, such as `io.github.your-name`. The default prefix is the
     author's, and a bundle ID can belong to only one team, so Xcode can't sign the app with it for you.

   Both the app and its UI test target read these two settings. The project itself names no team.
2. Connect the iPhone to the Mac with a cable and unlock it. Tap Trust This Computer.
3. On the iPhone, turn on Developer Mode in Settings › Privacy & Security. The iPhone restarts.
4. Open `PebbleRemote.xcodeproj`. Choose the PebbleRemote scheme and your iPhone, then press Run. The first build takes
   a few minutes.
5. If the iPhone says "Untrusted Developer", go to Settings › General › VPN & Device Management, trust your Apple ID,
   and press Run again.

The committed project was generated from `project.yml` by XcodeGen 2.46. If you change `project.yml`, run
`xcodegen generate` in the repository's root folder.

### Every 7 days

With a free Apple ID, Apple's signature lasts 7 days. After that the app stops opening until you install it again.
Installing over the old app keeps its pairing and settings. In the app, Settings › This Build shows when the current
build expires.

To renew it yourself, press Run in Xcode again with the iPhone connected, or run `scripts/renew.sh`. The script builds
the app, installs it on the paired iPhone with `xcrun devicectl`, and prints the new end date.

### Renewer: renewing on its own

`Renewer/` is a small Mac menu-bar app. It shows how many days the build has left. When 1 day or less is left and the
iPhone can be reached by cable or on the same Wi-Fi, it runs `scripts/renew.sh` for you. It never wakes the Mac.
`Renewer/README.md` has the details.

Build it, install it, then install the app once through `renew.sh` so the Renewer knows which build is on the iPhone:

```
swift build --package-path Renewer -c release --product PebbleRemoteRenewer
Renewer/install.sh --dry-run      # shows what it will do
Renewer/install.sh
scripts/renew.sh --commit HEAD
```

`Renewer/install.sh` builds nothing and needs no password. For your Mac user only, it puts in place:

- the app, at `~/Library/Application Support/PebbleRemoteRenewer/Pebble Remote Renewer.app`, signed ad hoc;
- a LaunchAgent, `~/Library/LaunchAgents/io.github.tohin003.PebbleRemoteRenewer.plist`, which starts the app at every
  login.

Once it runs, it also keeps in the same Application Support folder the state file that `renew.sh` writes, its own
record, and a git worktree of this repository that it builds in (about 300 MB). Its log is
`~/Library/Logs/PebbleRemoteRenewer.log`.

To remove it, run `Renewer/uninstall.sh`. It stops the app and removes the LaunchAgent and the app. Add `--all` to also
remove the worktree, the state file, the record and the log.

Until `renew.sh` has installed the app once, the Renewer reads the end date from Xcode's newest profile for the
author's bundle ID (`Renewer/Sources/PebbleRemoteRenewer/AppConfiguration.swift`). With your own prefix it shows
"No date" until that first install.

## Pairing

Pairing happens once, at home. Pebble's guide covers it step by step, with Tailscale for use away from home:
[docs/PEBBLE_REMOTE.md](https://github.com/tohin003/Pebble/blob/main/docs/PEBBLE_REMOTE.md).

In short: in Pebble, open Settings › iPhone, turn on Pebble Remote and choose Show a pairing code. In the app, scan the
code or paste the link. The Mac then shows six digits; pair only if the iPhone shows the same six.

## How it is secured

- **Keys in the Secure Enclave.** Pairing makes two P-256 keys in the iPhone's Secure Enclave. Their private halves
  never leave it. One key signs each connection; the other signs approvals. The simulator, which has no Secure
  Enclave, uses keys kept in its Keychain instead.
- **Face ID for approvals.** The approval key asks for Face ID for every signature. One check covers the approvals of
  the next 30 seconds. Enrolling a new face makes the key unusable, and you pair again. The app can also ask for
  Face ID when it opens (Settings › Unlock with Face ID, on by default).
- **Pinned TLS.** The app speaks TLS 1.3 only. It accepts only the key it pinned for your Mac at pairing: a
  certificate for any other key is refused, whoever signed it. Every connection is checked, because TLS session
  resumption is off.
- **No server in between.** The app connects only to Pebble on your Mac, at the addresses the pairing link and the Mac
  give it. It also looks for that Mac on your local network with Bonjour. No server of ours sits in between. Over
  Tailscale, Tailscale's relays may carry the encrypted traffic when the two devices can't connect directly.

Pebble's guide describes the Mac's side: the one-time pairing code, the six digits, and what the iPhone may and may
not do.

## Try it without a Mac

On the first screen, Try the Demo runs a simulated Pebble inside the app, with made-up chats and projects. The launch
argument `-demo` starts the app in the demo.

## Tests

- `swift test` runs the package's tests on the Mac. `scripts/swift.sh test` does the same, one build at a time, at a
  low priority.
- `swift test --package-path Renewer` runs the Renewer's tests.
- `python3 -I -B -m unittest discover -s bridge-mock -p 'test_*.py'`, from the repository's root, runs the tests of
  `bridge-mock/`. It needs a Python 3 whose `ssl` module supports TLS 1.3, such as the python.org installer's or
  Homebrew's (tested with 3.14). The `python3` that comes with macOS can't run it: its LibreSSL has no TLS 1.3.
- The PebbleRemoteUIAudit scheme is a UI test that taps through every screen of the demo.

Some tests compare the app's words with Pebble's own source. They run only when the environment variable
`PEBBLE_CHECKOUT` names a checkout of Pebble; otherwise they are skipped or check nothing. The view-format tests in
`Tests/PebbleProtocolTests/ViewSpecTests.swift` likewise run only when `pebble-ui-spec-v1/fixtures.json` sits in the
folder next to this repository.

## What is in this repository

| Path | What |
|---|---|
| `App/` | The app target: a thin shell over the Swift package, its Info.plist, icons and signing settings |
| `Sources/` | The Swift package: `PebbleProtocol` (the wire format), `PebbleRemoteKit` (connection, security, store, demo), `PebbleDesign` (Pebble's look and words on iOS), `PebbleRemoteUI` (every screen) |
| `Tests/` | The package's tests |
| `UIAudit/` | The UI test target |
| `bridge-mock/` | A stand-in for Pebble's side in Python: a mock bridge with a simulated Pebble, and a conformance checker for any bridge |
| `Renewer/` | The menu-bar app that renews the 7-day signature |
| `scripts/` | `swift.sh` (builds one at a time), `renew.sh` (build and install on the iPhone), `hold-status.sh`, `lint_copy.py` (the app's word rules) |

`scripts/hold-status.sh` lets the author's own scripts wait while Pebble runs timed benchmarks. It reads a status file
named by `PEBBLE_HOLD_STATUS_FILE`; without one it never waits.

Comments in the code refer to the bridge contract and to design notes under `docs/`. Those were working documents of
the app's development and are not published. The code, its tests and `bridge-mock/` are the reference for the protocol.

## Limits

- Not on the App Store. You build and install it yourself.
- With a free Apple ID, the app must be installed again every 7 days. The Renewer can do it for you.
- It needs Pebble 2.0 or later.
- It pairs with one Mac at a time.
- You can't show a view on the Mac's screen from the phone. No method of Pebble's bridge does that.
- You can't share an export's file from the phone. No method the phone may call returns the file itself.
- iPhone only. There is no iPad or Mac version.
- It has had internal reviews only. No independent security audit has been done.

## Licence

Apache License 2.0: see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

Pebble's character engine: bloub by Jérémy Perret (MIT). The pebble's shape and face in
`Sources/PebbleDesign/Avatar/` are ported from it.
