# bridge-mock: the reference bridge and its conformance checker

Lane C's kit for the bridge contract, **v0.3**: the contract document (not published), sections 3 (with 3.11)
and 4, plus claude-w's C1 to C7 (section 7) as the iOS side accepted them at 00:40. Lane C2 added **proposal v0.5**
(section 6, 10:50, accepted by claude-w at 10:53) on 2026-10-30: folders for "Connect a project", the rules for a new
folder, and opening things on the Mac (see "Proposal v0.5" below), and the two changes claude-w accepted at 10:49:
**X-1** (the person confirms each pairing on the Mac) and **S-05** (`remote.lock`, and an unlock that ends with the
device's last connection; see "X-1 and S-05" below). Lane F added **proposal v0.6** (section 6, 15:14) on 2026-10-30: a
new folder on the Mac, made from the phone (`remote.folder_create`, and the ten minutes in which a folder a device made
connects with the unlock alone; see "Proposal v0.6" below). Everything is Python 3 standard library (run it with
`python3 -I`); the TLS identity is made with `/usr/bin/openssl`, and the screenshot test pattern is made a JPEG with
the built-in `/usr/bin/sips`.

| File | What |
|---|---|
| `mock_bridge.py` | The whole contract (v0.3, v0.5 and v0.6) in front of a **simulated Pebble**. The app's end-to-end tests and the first real-iPhone tests use it. |
| `conformance.py` | Plays the iPhone and judges any bridge (this mock or claude-w's real one) against the contract, as a PASS/FAIL/SKIP table: 35 PASS and 2 SKIP for v0.3; with v0.5 (8 rows), v0.6 (3), X-1 (2) and S-05 (2) 50 PASS and 2 SKIP. |
| `remote_wire.py` | Shared helpers: ECDSA P-256 (pure Python), strict DER, the SPKI pin, `T_pair`/`T_hello`/`T_proof`, the pairing link, RFC 6455 WebSocket, private-address rules, a JPEG size reader, the contract's tables (3.6, 3.7, C1, v0.5's opening methods), X-1's confirmation code and its vectors, a copy of Pebble's protected-folder list, and v0.6's rules for the name of a new folder. |
| `test_mock.py` | Unit tests, parity tests against the Pebble checkout, and the mock on ephemeral ports with conformance run against it (177 tests with `test_security_review.py`). |
| `state/` | Made at first start, gitignored, folder 700, files 600: `tls-key.pem`, `tls-cert.pem`, `bridge.json` (bridge id), `devices.json` (paired phones). |

## Run the mock for the app (this Mac)

```sh
python3 -I bridge-mock/mock_bridge.py --print-pairing                 # 127.0.0.1, an ephemeral port
python3 -I bridge-mock/mock_bridge.py --print-pairing --speed 4 --state-dir /tmp/mock-state   # tests
```

stdout has one fact per line, for scripts: `PORT=`, `PIN=`, `BID=`, `ENDPOINTS=`, `PID=`, `PAIRING_LINK=` (only with
`--print-pairing` or `--copy`), then `READY=1`; later `PAIRING_CODE=123456` each time a pairing waits for the person to
confirm its code (X-1). stderr is the log, content-free: connection numbers, method names, refusal codes and timings,
never message text, parameters, keys or the pairing link's code. **The one exception** is that six-digit confirmation
code, which the Mac and the phone both show ("pairing code 123456: confirm on the Mac").

- **Pairing is off unless you ask** (contract 4.1). `--print-pairing` opens it at start; `kill -USR1 <PID>` opens a new
  link at any time (5 minutes, one phone, at most 5 tries; a new link replaces the old one).
- `kill -USR2 <PID>` stops or starts the simulated Pebble: a `remote.pebble` event, then Pebble's calls get
  `pebble_offline`.
- Options:
  - `--host`, `--port` (0 = ephemeral), `--state-dir`, `--name` (the Mac's name on the phone; default this Mac's);
  - `--speed` (2 = everything twice as fast), `--battery` (the Mac on battery), `--idle-timeout` (default 45 s),
    `--quiet`;
  - `--unlock-seconds` (C1's window, default 900), `--no-screen-recording` (C3's refusal, as a Mac without Screen
    Recording permission gives it), `--limit-loopback` (C6's handshake limit on 127.0.0.1 too, for tests);
  - `--folders-root DIR` (v0.5): `remote.folders` lists this folder as the home folder, a test tree, instead of this
    Mac's real home folder (the folder must exist). Without it the mock lists the real home folder, as the person's own
    phone browses it: subfolders only, no hidden or protected ones, never a file or its name. **v0.6:
    `remote.folder_create` makes its folders there for real** (in the tree, or in the real home folder without the
    option). The tests and the conformance run in `test_mock.py` always use a temporary tree;
  - `--pair-confirm auto|ask|refuse` (X-1; default `auto`): how the Mac confirms a pairing once `pair` verifies.
    `auto` confirms after about 1.5 s, so the phone has time to show its code; `ask` prints the code on stderr and
    reads `y` or `n` from stdin (the Mac's person at the keyboard); `refuse` cancels every pairing (for tests).
    `--pair-confirm-timeout SECONDS` (default 120): no answer for this long is a refusal (shorter for tests of the
    two-minute rule); `--pair-confirm-delay SECONDS` (default 1.5): `auto`'s wait (shorter for tests);
  - `--proof-version 2` (or `PEBBLE_MOCK_PROOF_VERSION=2` in the environment): v0.2's `T_proof`, for a client that
    has not switched yet. Default 3.
- `--host` must be a loopback, private or Tailscale address (C6); a public or wildcard address is refused.

## Run the mock for the real iPhone (after Xcode, outside a HOLD)

```sh
python3 -I bridge-mock/mock_bridge.py --lan --port 47800 --print-pairing --copy --bonjour
```

`--lan` listens on the Mac's Wi-Fi address (only if it is a private one, C6), any Tailscale `100.x` address, and
127.0.0.1 for checks here. It puts the Wi-Fi address, `<LocalHostName>.local` and the Tailscale addresses in the link.
`--copy` puts the link on the clipboard, so Universal Clipboard pastes it on the iPhone (Pairing, Paste link).
`--bonjour` advertises `_pebble-remote._tcp` with the built-in `dns-sd -R`: the instance is named by the bridge id
(C6), with TXT `v=1` and `bid=`. The first time, macOS asks whether `python3` may accept incoming connections (allow
it), and iOS asks Pebble Remote for Local Network access. Keep the same `--state-dir` between runs: the key, and so the
pin and the pairing, survive restarts (a restart changes the epoch, so the phone gets `resumed:false` and refetches).

Pairing now waits for the Mac's confirmation (X-1). With the default `--pair-confirm auto` the phone only waits about
1.5 s longer; add `--pair-confirm ask` to confirm by hand (type `y` after checking that the iPhone shows the code the
terminal shows). The phone's client has to wait for `paired` up to two minutes, and show the code, for that.

## Run conformance

```sh
python3 -I bridge-mock/conformance.py --link '<a fresh pairing link>'
```

**For claude-w, against the real bridge:** turn Remote on, show a new pairing link in Pebble's settings, copy it, and
run the line above while Pebble is idle (no task running: one check sends a message). **Pairing waits for a person
(X-1):** the checker prints "pairing code 123456: confirm on the Mac"; the Mac shows the same six digits, and the
person confirms there (the checker waits up to 130 s, `--pair-wait`). Run it twice to cover C6:

- on loopback (`--endpoint 127.0.0.1:<port>`), where the handshake limit does not apply and its row is SKIP;
- against the LAN address (`--endpoint <LAN address>:<port> --bonjour`), where the checker keeps itself under 9
  connections a minute (the run then takes about two minutes), tests the 10-a-minute limit last, and resolves the
  Bonjour instance.

Exit code 0 only when no row FAILs. Options: `--endpoint host:port`, `--timeout` (each answer, default 10 s),
`--run-timeout` (the test run's end, default 120 s), `--keep-device`, `--no-screenshot`, `--no-connect` (v0.5: do not
connect a folder with a proof), `--no-link-probe` (v0.5: do not make two links in the home folder),
`--no-create-probe` (v0.6: do not ask for empty folders in the home folder), `--pair-wait`
(X-1: seconds to wait for the person, default 130), `--expect-pair-refused` (X-1: see below), `--bonjour`,
`--json <file>`, `--verbose` (every frame received, content-free).

**A second run covers the refusal:** `--expect-pair-refused` with another fresh link runs only the transport row and
two X-1 rows: the checker prints the code, the person **cancels** on the Mac (or leaves it unanswered), and the checker
expects `bye` `bad_code` with words, the connection closed (within two minutes), and the pairing code spent. Against
the mock: start it with `--pair-confirm refuse`.

**Proposal v0.5 is checked when `welcome.methods` includes `remote.folders`**; a bridge without it is judged by v0.3
alone and gets one SKIP row. (A bridge that offers `open_url` and the other opening methods without `remote.folders`
fails the welcome row: v0.3 excludes them, and v0.5 starts with `remote.folders`.) **Proposal v0.6 is checked when it
includes `remote.folder_create`**; a bridge with `remote.folders` but without it is judged by v0.5 alone and gets one SKIP
row, and one that offers it without `remote.folders` fails the welcome row.

What it changes on the Mac:

- one paired device, removed again by its last checks;
- one conversation it creates, with the message "Pebble Remote conformance check: reply with the single word ok." and
  Pebble's short reply (one small model request; delete the conversation afterwards if you like);
- one `setting` `permissions` call that writes the value it just read, and one plain setting (`theme`, or another
  key not listed as elevated) written with its current value;
- one screenshot of the Mac's screen, kept in memory only to check its JPEG, never written or shown (the Mac shows its
  notice). Pass `--no-screenshot` to skip it;
- with v0.5, on loopback only: **two links in the home folder**, named `pebble-remote-conformance-<random>-in` and
  `-out` (to a folder inside home and to `/usr`), made to try the link rule and removed again when that row is done
  (skip it with `--no-link-probe`; it writes only in this user's home folder or a tree in a temporary folder);
- with v0.5: it lists folders (the names are never printed), connects **one folder of the home folder** to its own
  conversation with a proof and takes it off again (the Companion again; pass `--no-connect` to skip it), and makes a
  few empty conversations (an empty conversation is not listed until it has a message). It never opens anything on the
  Mac, and never goes into Desktop, Documents, Downloads, Library, Movies, Music, Pictures or Public, where macOS asks
  the person first;
- with v0.6, on loopback only: **a few empty folders in the home folder**, named
  `pebble-remote-conformance-<random>-made`, `-dup`, `-connect` and the like, which the bridge makes for the checker
  with a proof and the checker removes at once (`rmdir`, so only an empty folder goes), even when a row fails (skip it
  with `--no-create-probe`; like the links, it writes only in this user's home folder or a tree in a temporary
  folder). A row that stops in the middle (the checker killed) can leave one behind: it is empty, and its name says
  where it came from. The folders a faulty bridge makes where it must not (a hidden folder, one with a colon in its
  name, one in the folder above home) are looked for and removed too.

Calls it expects to be refused are sent with values or parameters that change nothing even if a bridge wrongly
relayed them (current setting values; a parameter no Pebble route takes). The v0.5 exceptions, which a correct bridge
refuses and a broken one would act on: a plain `set_workspace` or `new_chat` for a listed folder (the checker puts its
conversation back at once), a proof for `/usr` as a project (same), and `browser_start`, which takes any parameters and
goes last.

The rows, in order (52 in all against the mock: 50 PASS and 2 SKIP; the rows marked v0.5 run only when the bridge
offers `remote.folders`, and those marked v0.6 only when it offers `remote.folder_create` too; with
`--expect-pair-refused` the run is rows 1, X-1's refusal and its spent code instead):

1. transport: TLS 1.3, the certificate's SPKI pin equals the link's, the subprotocol `pebble-remote.v1` is chosen;
2. challenge format (`v`, `bid`, a 32-byte base64url nonce, the Mac's time in unix ms; a fresh nonce per connection);
3. frames before `hello`/`pair` get no answer (4.2);
4. a wrong pairing code gets `bye` `bad_code` with words (3.11 item 1);
5. the right code with a pair whose `approve_sig` is not by the approve key gets `bye` `bad_signature`, and the code
   stays usable (a refused pair is one of its five tries);
6. pairing works: `paired` with a `device_id`, then `welcome` (the checker prints the code the Mac must show, and
   waits up to `--pair-wait` for the person);
7. **X-1:** the six-digit code: the checker's formula gives the fixed T_pair vectors, and this pairing's code is
   printed for the person to compare with the Mac's;
8. **X-1:** `paired` comes only after the person confirms on the Mac, not at once (at least 1 s after `pair`: a
   bridge that confirms by itself should wait about 1.5 s);
9. welcome fields: `v`, `epoch`, `seq`, `resumed:false`, `bridge`, `pebble`, `methods` without anything 3.7 excludes
   (v0.5: the nine opening methods are not excluded when `remote.folders` is offered), `elevated` naming every offered
   3.6 method plus `remote.unlock` and `setting:permissions`, entries that are offered methods or `setting:<key>`,
   `unlock_seconds`, `limits`;
10. the code cannot be used twice (`bye` `bad_code`);
11. a bad `hello` is refused with `bad_signature` (the wrong key; signed for another connection's nonce), and the
    paired connection is not disturbed;
12. C1: reads work before any unlock (`state`, `remote.ping`, `remote.devices` with `current`, `chat_search`,
    `remote.status`);
13. C6: every endpoint in the link and in `remote.status` is private (loopback, RFC 1918, link-local, ULA, Tailscale's
    `100.64/10`, `.local`, `.ts.net`);
14. C1: acting before the unlock gets `unlock_required` (`new_chat`, `model_profiles`, `remote.keep_awake`,
    `remote.screenshot`);
15. **v0.5:** `remote.folders` before the unlock gets `unlock_required` (it shows the names of the Mac's folders);
16. `approve`, `setting` `permissions` and `remote.unlock` without a proof get `proof_required`;
17. bad proofs get `bad_proof`: the device key, a `ts` two minutes old or two minutes ahead, `params_json` changed after
    signing, another method, another epoch, another connection's nonce, another idem, v0.2's transcript; and none of
    them unlocked;
18. C1: `remote.unlock` with a proof answers `unlocked_until` (unix ms, `unlock_seconds` ahead), then `new_chat` works;
19. a good proof works (`setting` `permissions`; an `approve` that reaches Pebble's own refusal), and reusing its
    request id gets `bad_proof`;
20. calls outside the allowlist get `not_allowed` (local files, sign-ins, installs, native-only, an unknown name; with
    v0.3 also the Mac's screen: 16 calls, with v0.5 12, because the opening methods are allowed and elevated);
21. every `setting:<key>` in `elevated` needs a proof; a plain key works without one (v0.3 item 5);
22. a setting key cannot dodge the proof: given twice, not a string, another case, a trailing space (security review);
23. request ids with a space, a dot, 65 characters, a line break or nothing get `bad_request`; 64 in the charset pass
    (item 2);
24. `idem`: a `new_chat` repeat returns the first answer; `chat_rename` and a plain `setting` without one get
    `bad_request` (item 4);
25. **S-05:** `remote.lock` (no idem, params `{}`) answers `{}` and the next call that acts gets `unlock_required`;
    locked already, it still answers `{}`; then the checker unlocks again with a proof;
26. **v0.5:** `remote.folders` lists the home folder (`path` null and left out give the same answer; the shape, the
    order, at most 500, no hidden or protected folder), goes down into a folder (`path`, `parent`) and back up;
27. **v0.5:** `remote.folders` refuses `/`, `/etc`, `/usr`, `<home>/..`, the folder above home and the like with
    `not_allowed`, and a path that is not a string;
28. **v0.5:** hidden and protected folders are left out of the listing, and asking for `.ssh`, `.pebble`, `.claude` or
    `PebbleBackups` is refused;
29. **v0.5:** a path that is itself a link, or resolves outside home, gets `not_allowed` in `remote.folders`, and in
    `set_workspace` and `new_chat` with a proof: a link to a folder inside home, a link to `/usr`, a path below it,
    a link written with a trailing slash; the links are not listed (loopback only; SKIP elsewhere and with
    `--no-link-probe`);
30. **v0.5:** `set_workspace`: `null` and a project a conversation uses need only the unlock; a new listed folder gets
    `proof_required`; a folder the listing would not show (`/usr` must be `not_allowed`, `.ssh`) is refused even with
    a proof; with a proof a listed folder is connected (`get_chat` shows it), then taken off again (skipped with
    `--no-connect`);
31. **v0.5:** `new_chat` with a project in use keeps it as the workspace; with a new folder it needs the same proof
    (otherwise it is a way around `set_workspace`: see "Contract issues", 8);
32. **v0.5:** the nine opening methods are in `welcome.methods` and `welcome.elevated`, and each one without a proof
    gets `proof_required` (sent with a parameter no Pebble route takes: nothing opens even if a bridge relays it);
33. **v0.6:** `remote.folder_create {parent, name}` without a proof gets `proof_required` and makes nothing; with one it
    makes one empty folder in the home folder, answers `{path, name, is_project: false}` (path = parent + name), and the
    listing shows it (loopback only, the folder is removed again; SKIP elsewhere and with `--no-create-probe`);
34. **v0.6:** with a proof, a name that is empty, blanks, `.`, `..`, a leading dot, with `/` or `:`, a line break or a
    control character, 256 bytes, or not a string gets `bad_request`; a parent that is `/`, `/usr`, `<home>/..`, the
    folder above home, hidden or protected, a link (inside home or out of it), not a string or not there is refused
    (`not_allowed`); none of them made a folder (the checker looks, and removes what a faulty bridge made); a name
    already there gets words and **no code**;
35. **v0.6:** a folder this device just made connects with the unlock alone: `set_workspace` and `new_chat {workspace}`
    with exactly its path need no proof (it counts as known for ten minutes), and another listed folder still gets
    `proof_required`; the checker puts its conversation back in the Companion and removes the folder (SKIP with
    `--no-connect` and where it cannot write);
36. resume: `send`, close at once, reconnect with `resume`: `resumed:true`, the missed events replayed in order with
    no gap, before live ones; the `send` repeated with the same `idem` returns the first answer and the message is in
    the conversation once (S-05: the unlock ended with the first connection, so the checker unlocks again on the new
    one when it is asked to, as the phone does);
37. C2: the accepted `remote.unlock` frame sent again on another connection, verbatim and under a new id, gets
    `bad_proof`;
38. events: `seq`, `event`, `data`, `ts` (unix ms) on each; `run` events carry `{chat_id, run_id, state}`; C4: an
    `activity` event for the run arrives; the reply's `token` texts join to its saved text;
39. item 7: bridge times are unix ms; the `remote.devices` event, if one was seen, carries the device array;
40. a stale epoch gets `resumed:false`;
41. a second connection replaces the first: `bye` `replaced` with words, then the close;
42. a request over `limits.max_request` that parses gets `res` `too_large` with its id, and the connection stays (item 6);
43. WebSocket: a ping is answered; a request in three fragments with a ping between them is reassembled;
44. C3: `remote.screenshot` gives base64 JPEGs whose own headers match `width`/`height`, long side at most 2,560,
    `taken_at` in unix ms; asking for one display gives that one; a display that does not exist is refused. A Mac
    without Screen Recording permission may refuse in words: that passes, with nothing to check;
45. a burst of 40 requests gets some `rate_limited`;
46. a frame over `max_request` that cannot parse gets `bye` `too_large`, then the close (item 6);
47. an unknown device gets `bye` `unknown_device`;
48. requests nested 20,000 and 300,000 levels deep leave the bridge serving (security review);
49. **S-05:** the unlock ends when the device's last connection closes: unlock on a connection, close it, connect
    again: the next call that acts gets `unlock_required`;
50. `remote.revoke_device` on itself answers, then `bye` `revoked`; the removed key gets `bye` `revoked` (or
    `unknown_device`);
51. C6: twelve quick handshakes from one address meet a refusal (only against a non-loopback endpoint; else SKIP);
52. C6: the Bonjour instance named by the bridge id resolves with `v=1` and `bid=` (only with `--bonjour`; else SKIP).

With `--expect-pair-refused`: **X-1:** a pairing the person cancels (or leaves unanswered for two minutes) gets `bye`
`bad_code` with words, and the connection closes; **X-1:** the pairing code is spent after a refusal (a second `pair`
with it gets `bye` `bad_code` at once).

What a FAIL says is written for the person reading the table, and carries no folder name: counts, method names and
codes only.

## X-1 and S-05 (claude-w's answers of 2026-10-30 10:49)

### X-1: the person confirms each pairing on the Mac

- After `pair` verifies (the code, then both signatures), the Mac shows a six-digit code and the phone shows the same
  one. The bridge sends `paired` (then `welcome`) **only after the person confirms on the Mac that the two codes
  match.** Until then nothing is stored, the pairing code is already spent (a second phone with the same link gets
  `bye` `bad_code`), and the connection may stay silent for up to two minutes.
- **Cancel, or two minutes without an answer: `bye` `bad_code`** with the words "Pairing wasn't confirmed on your Mac.
  Show a new pairing link there and try again.", then the close. The pairing code stays spent: it takes a new link. A
  phone that leaves while the Mac waits is not stored either (and the code stays spent).
- **The code:** the first 4 bytes of SHA-256 over the UTF-8 bytes of `pebble-remote/v1/sas\n` followed by T_pair (the
  very T_pair the pair signatures cover, section 3.2), read as a big-endian unsigned integer, mod 1,000,000,
  zero-padded to 6 digits. `remote_wire.sas_code(t_pair)`; both sides compute it from their own copy of T_pair.
- **Golden vectors** (`remote_wire.SAS_VECTORS`; the tests assert them with the hash written out again). T_pair is
  `pebble-remote/v1/pair\n` and then bid, nonce, pin, code, device_key and approve_key, each followed by `\n`:

  | | T_pair fields | SHA-256 over `pebble-remote/v1/sas\n` + T_pair | first 4 bytes | integer | code |
  |---|---|---|---|---|---|
  | 1 | `b-1`, `n-1`, `p-1`, `c-1`, `dk-1`, `ak-1` | `57065e008e6e8ae233d92ebd1b61315ad0cb083f1a2d2ec6f428b7d804b937b5` | `57065e00` | 1460035072 | **`035072`** (the zero is kept) |
  | 2 | `b-AAECAwQFBgcICQoL`, `AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8`, `uBxfZqYw5vyQji5sLR4Ex6QEFGKWKNk-v7nH6PPPyFM`, `ZGVmZ2hpamtsbW5vcHFycw`, `BAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8`, `BEBBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn8` | `9d6a609c86ea7ca392c70ae278859a96aa42ee081bf53e9f23339ab73dde43c6` | `9d6a609c` | 2640994460 | **`994460`** |

  Vector 2's fields are realistic ones (a 43-character pin, a 22-character code, 65-byte keys), all base64url without
  padding: bid `b-` and the bytes 0 to 11; nonce the bytes 0 to 31; pin the SHA-256 of the ASCII text
  `pebble-remote golden pin`; code the bytes 100 to 115; device_key the byte `04` and then the bytes 0 to 63;
  approve_key `04` and then 64 to 127 (not real curve points: the formula only hashes them).
- **In the mock:** `--pair-confirm auto|ask|refuse` (default `auto`: confirm after about 1.5 s, so the phone has time to
  show its code; `ask`: print the code and read `y` or `n` from stdin; `refuse`: send the `bye`), `--pair-confirm-timeout
  SECONDS` (default 120) and `--pair-confirm-delay SECONDS` (default 1.5). The code is logged ("pairing code 123456:
  confirm on the Mac", the one log line with a code) and printed as `PAIRING_CODE=123456` on stdout. While a pairing
  waits, the 30 s authentication and 45 s idle timers do not run for its connection (its own timeout ends the wait).
- **For the phone's lane:** wait for `paired` up to two minutes, show the code at once, and keep answering pings; the
  Swift `LiveClient.pair` waits `readTimeout` (10 s), which is enough for `auto` and not for a person.
- **Conformance:** the checker prints its own code before sending `pair` (so the person can compare it with the Mac's),
  checks its formula against the vectors, and requires `paired` to come at least 1 s after `pair`. It cannot see what
  the Mac shows. `--expect-pair-refused` covers the refusal and the spent code (a second run, with a person who
  cancels, or `--pair-confirm refuse` on the mock).

### S-05: `remote.lock`, and an unlock that ends with the last connection

- **`remote.lock`** is a read (like C1's 14, so it joins them: 15): params `{}`, result `{}`, no proof, no idem, and it
  works whether or not the device is unlocked. It ends **that device's** unlock at once; the next call that acts gets
  `unlock_required`, and an elevated call or `remote.unlock` unlocks again. It is in `welcome.methods`, not in
  `welcome.elevated`.
- **A device's unlock also ends when its last connection closes.** A newer connection of the same device replaces the
  older one (`bye` `replaced`); the older one closing is not the last. So after a reconnect, or after the app has been
  away, the first call that acts needs Face ID again: the phone's client already answers `unlock_required` by asking
  for it and trying once more.

## Proposal v0.5: shapes, rules and codes

The iOS side's proposal of 2026-10-30 10:50 (bridge file, section 6), accepted by claude-w at 10:53 with one addition
(a `path` that is a link gets `not_allowed`). `welcome.methods` has `remote.folders` and the nine opening methods;
`welcome.elevated` has the nine. The phone builds against exactly these shapes.

### `remote.folders {path?}`

Needs the unlock (C1; it is not one of the reads), no proof. It is read-only, so `idem` is optional (the phone's client
sends one, which is fine). `path` null or left out is the home folder; every path in an answer is absolute and spelled
as the listing spells it. Answers `result`:

```json
{"home": "/Users/<name>", "path": "/Users/<name>/Projects", "parent": "/Users/<name>",
 "folders": [{"name": "app", "path": "/Users/<name>/Projects/app", "is_project": true}]}
```

- **`parent`** is the folder above `path`, and `null` when `path` is the home folder (nothing goes above home).
- **`folders`:** subfolders of `path` only, never files, never file names or contents. Sorted by name, ignoring case, at
  most 500 (more are cut off without a flag). `is_project` is true when the folder holds `.git`, a folder or the file a
  worktree has. Nothing else is in an answer: no sizes, no times, no `truncated`.
- **Left out of every listing:** hidden folders (a name that starts with a dot, or macOS's hidden flag, which `~/Library`
  has); Pebble's protected list (the Shell sandbox's `PROTECTED_HOME`, `PROTECTED_PREFIX` and `PROTECTED_NAME`, copied
  in `remote_wire.py`: keys, passwords, browser data, Messages, Mail, Pebble's own data and backups, other agents'
  folders, shell histories; a folder named `secrets`, `credentials` or `*.key` and the like); the mock's own state
  folder; links.
- **Refusals:**

| What | Answer |
|---|---|
| before the unlock | `ok:false`, code `unlock_required` |
| `path` not a string, empty, relative, with a NUL byte, over 4,096 characters | code `bad_request` |
| a place outside home, a `..` in the path, a link (the path, or a folder above it), a doubled slash | code `not_allowed`, "Pebble Remote shows folders inside your home folder only." |
| a hidden or protected folder, or one below it, **whether or not it exists** | code `not_allowed`, "Pebble keeps hidden and private folders off your iPhone." |
| a folder that is not there, or a file | `ok:false`, **no code**, "Choose a folder that exists." (Pebble's words) |
| a folder the mock may not read | `ok:false`, no code, "Pebble can't open that folder on your Mac." |

A path must be the real path of a folder in home, with every folder from home down to it one that a listing shows. So
whatever a phone gets from `path`, `parent` and `folders[].path` can be sent back as it is.

### `set_workspace {id, path}` and `new_chat {workspace}`

`new_chat` follows the same rule, because a `new_chat` that took any folder with the unlock alone would be a way around
`set_workspace` (see "Contract issues", 8). **Lane N: both calls may answer `proof_required`; retry that call elevated.**

| `path` / `workspace` | Without a proof | With a proof (`callElevated`) |
|---|---|---|
| `null` (the Companion), or `""`, or left out in `new_chat` | works with the unlock | works |
| a project a conversation on the Mac uses (a string in `state.chats[].workspace`) | works with the unlock | works |
| anything else: a listed folder, a hidden one, one that is not there, even a number or a list | **`proof_required`**, "Confirm with Face ID to do this.", locked or not, **the same answer for all of them** | a folder `remote.folders` would list (below home, never home itself): works. Anything else: code `not_allowed`, "Choose a folder from the list. Pebble Remote can't connect that one." |

- The same answer for every new value matters: a phone that has not proved itself learns nothing about the Mac's
  folders from `proof_required`. It also means a locked phone gets `proof_required`, not `unlock_required` (the proof
  unlocks it).
- **A link is not a folder the listing shows** (claude-w's 10:53 addition): with a proof, a `path` that is itself a
  link (to a folder inside home, to somewhere else, to a file, to nothing, even with a trailing slash), or lies below
  one, gets `not_allowed`; without a proof it still gets `proof_required`, like every new value. The same holds for
  the `--folders-root`: it is the home folder in these rules.
- A connected folder becomes a project a conversation uses, so the next call for it needs only the unlock.
- `set_workspace` answers the conversation as `get_chat` shows it (with `workspace`); `new_chat` the same, and the
  workspace is kept as given (Pebble stores the folder resolved; the bridge lets only real paths through). An empty
  conversation is not in `state.chats` until it has a message.
- After the proof, Pebble's own refusals pass through with no code, as ever: "Stop the current task before changing its
  project." while a task runs, "Conversation not found.", "Choose a folder that exists.".

### Opening things on the Mac

`open_url`, `open_app`, `view_stage`, `artifact_view_open`, `browser_start`, `browser_open_tab`, `quiz_share`,
`terminal_propose` and `process_terminal` are allowed and **all elevated**: without a proof, `proof_required` (locked or
not); `idem` goes on every one. **The mock never opens anything.** With a proof it logs a content-free
"simulated Pebble would open a web page on the Mac; nothing was opened" and answers `result` **`{"ok": true}`**, where
Pebble's own answers differ (`open_url` answers `true`, `open_app` a review card), so a phone should not read
these results. It does check the parameters, with Pebble's words:

| Call | Parameters | Refusals (no code) |
|---|---|---|
| `open_url` | `{url}` | "Only public HTTPS links can be opened." (not https, no host, a user name or password, over 3,000 characters); a local or private address or name: "Only public HTTPS sources are allowed. Local and private networks are blocked." |
| `browser_open_tab` | `{url}` | "Open an https address, or an http address on this Mac." |
| `open_app` | `{id, app_id}` | "Conversation not found.", "Select an installed app." |
| `artifact_view_open` | `{chat_id, id, revision}` | "Conversation not found.", "Open the current active HTML revision for native review." |
| `quiz_share` | `{chat_id, attempt_id, surface?}` | "Conversation not found.", "Quiz attempt not found." |
| `process_terminal` | `{id, run_id, process_id}` | "Conversation not found.", "Run not found in this conversation.", "Process not found in this run." |
| `view_stage`, `browser_start` | any | none |

Wrong or missing parameters give Pebble's "Pebble couldn't do that because of an internal error. It is recorded in
Pebble's log."

**`terminal_propose {id, command, network?}`** is the composer's "Terminal command": it makes a **review card** in that
conversation, as Pebble's review does, and nothing runs. Result `{"status": "awaiting_user_approval", "action_id": "...",
"kind": "command"}`; the card is a pending `command` action (`payload`: `command`, `argv`, `network`, `root` = the
conversation's project, `requires_review`), sent in an `actions` event and in `get_chat`. The person approves it
(`approve`, elevated) or rejects it (`reject`); the mock's approval answers `exit_code` 0 and the output "(Simulated:
nothing was run on this Mac.)" (the canned test output for `npm test`). Refusals, with Pebble's words: a running task
("Wait for the current task before starting a terminal command."), a conversation with no project ("Select a project
folder first."), and a command that is empty, over 4,000 characters, on more than one line, with `$(...)`, a backtick or
`${...}`, with a pipe, redirection or `;`/`&` ("Enter a single command shorter than 4000 characters.", "Command
substitutions and environment overrides are blocked.", "Run one command at a time. Pipes, redirections and chained
shell commands are blocked.").

### `attach_url {id, url}`

Adds a source to the conversation (a simulated fetch: nothing leaves this Mac, and every source has 2,400
characters). Needs the unlock and an `idem`. Result `{"id", "name", "characters"}` (`name` is the URL). Checked in
Pebble's order: "Web access is disabled in Permissions." (the `web` switch), "Conversation not found.", then the address:
"Enter a public https:// URL without credentials or a custom port." (not https, no host, a user name or password, a port
other than 443, a space or control character), "Use a public URL shorter than 3,000 characters.", or, for a local or
private address or name, "Only public HTTPS sources are allowed. Local and private networks are blocked."; and "Use up
to ten sources per message." The next `send` with `source_ids` carries the source as an attachment of kind `url`.

## Proposal v0.6: a new folder, made from the phone

The iOS side's proposal of 2026-10-30 15:14 (bridge file, section 6): the person asked for a button that makes a new folder
on the Mac and connects it, from the phone. Under R6 it is
part of "Connect a project". `welcome.methods` has `remote.folder_create`, and `welcome.elevated` lists it.

### `remote.folder_create {parent, name}`

**Elevated** (a Face ID proof, because it writes to the Mac's disk) and not a read, so `idem` goes on it. Without a proof:
`proof_required`, locked or not, and nothing is made. The proof unlocks the phone, as every proof does (C1). It makes
**one empty folder, for real**: in this Mac's home folder, or in the test tree of `--folders-root`. Result:

```json
{"path": "/Users/<name>/Projects/my-app", "name": "my-app", "is_project": false}
```

That is an entry as `remote.folders` gives it, so `path` can be sent back as it is (to `remote.folders`, `set_workspace`,
`new_chat`).

- **`parent`:** an absolute path that `remote.folders` would list, **the home folder included**. The rules are the
  listing's: a place outside home, a `..`, a doubled slash, a link (the path, or a folder above it), a hidden or
  protected folder (whether or not it exists) get `not_allowed` ("Pebble Remote shows folders inside your home folder
  only.", "Pebble keeps hidden and private folders off your iPhone."). A parent that is not a string, or left out (`null`
  is not "home" here: the phone always sends the listing's `path`), is `bad_request`. A folder that is not there, or a
  file, gets "Choose a folder that exists." and no code. Nothing above the parent is ever made.
- **`name`:** the text is **trimmed** (every Unicode separator, the tab, the line breaks U+000A to U+000D and U+0085; a
  zero-width space stays), then must be 1 to 255 bytes of UTF-8 with no `/` or `:`, no control characters (Unicode
  category Cc), not `.` or `..`, and no leading dot. A name outside the rules is **`bad_request`**, with words that say
  which rule:

| Rule | Words (code `bad_request`) |
|---|---|
| empty (or blanks) | "Enter a name for the folder." |
| over 255 bytes | "That name is too long. Use a shorter one." |
| `/` or `:` | "A folder name can't contain / or :." |
| a control character | "A folder name can't contain line breaks or other control characters." |
| `.`, `..`, a leading dot | "A folder name can't start with a dot, which would make it a hidden folder." |
| a lone surrogate (JSON can carry one) | "That name can't be used for a folder." |
| **the mock's own addition:** a name the listing would leave out (`secrets`, `credentials`, `*.key`, `*.env`, a name on Pebble's protected list) | "Pebble keeps folders with that name off your iPhone. Choose another name." |

  The last rule is the mock's, not the proposal's: a folder `remote.folders` hides could never be shown or connected, so
  the phone would make it and then not find it (see "Contract issues", 15).
- **One empty folder:** never an intermediate folder, nothing inside it. It is made inside the folder that was just
  checked (the folder is opened without following a link, and the new one is made relative to it), so a parent swapped
  for a link a moment later is not followed. The disk decides what is already there: a name already in the parent (a
  folder, or a file; also the same name in another case on a case-insensitive disk) gets **"A folder with that name is
  already there."** and **no code**, and two phones asking for the same name make it once. A write that fails gets
  "Pebble can't add a folder there." (no permission) or "Pebble couldn't make that folder on your Mac." (anything else),
  no code. Every one of these words is Pebble's style and says nothing about the Mac's paths.
- **Recorded on the Mac:** the mock logs "device d1234 made a folder", **without its name**, and nothing else (the log
  stays content-free; the real bridge adds C7's notice, "Pebble Remote made a folder: <name>").

### The ten minutes: one Face ID for "make it and connect it"

A folder this device made in the last ten minutes (`MADE_FOLDER_SECONDS`, 600) counts as **known for this device**. So
`set_workspace {id, path}` and `new_chat {workspace}` with **exactly that path** need only the unlock, as a project a
conversation uses does. The memory is exact and small:

- **That path only:** the string `remote.folder_create` answered. A path below it, the same path with a trailing slash,
  another listed folder, or the parent are as before (`proof_required` for a new folder).
- **That device only:** another paired phone gets `proof_required`. (Once a conversation uses the folder, it is a project
  in use for every device, as in v0.5.)
- **Ten minutes, then a proof again:** measured from the `remote.folder_create` answer; at most 64 folders are
  remembered per device (the oldest go first); a removed device is forgotten.
- **Still a listed folder:** the bridge's other rule stands. If the folder is gone, or has become a link, since it was
  made, the plain call is refused (`not_allowed`, "Choose a folder from the list. Pebble Remote can't connect that
  one."); the memory never lets a folder through that the listing would not show.
- **The unlock still applies:** a locked phone gets `unlock_required`, not `proof_required`, and unlocks with Face ID as
  always; the memory survives it.
- An elevated `set_workspace` or `new_chat` for that folder works as ever.

A phone that makes a folder and connects it at once therefore asks for Face ID once. A bridge that does not remember it
answers `proof_required` to the plain call, and the phone retries that call elevated, so nothing breaks (a second Face ID).

## What the mock implements

- **3.1, transport:** WebSocket over TLS 1.3 at `/pebble-remote/v1` with subprotocol `pebble-remote.v1` (handshake,
  masking, fragmentation, ping/pong, close codes, 1 MiB hard frame cap); an ECDSA P-256 self-signed certificate,
  re-issued with the same key when missing or near expiry; TCP_NODELAY.
- **3.2, pairing:** a 16-byte code, 5-minute expiry, single use, 5 tries, constant-time comparison, both signatures
  over `T_pair`; `bye` `bad_code` for a wrong, used or expired code; the `remote.devices` event after the welcome.
  **X-1:** after the signatures verify, the code is spent and `paired` waits for the person's confirmation of the
  six-digit code (`--pair-confirm`); a cancel, no answer for two minutes, or a phone that leaves is `bye` `bad_code`
  (or nothing stored).
- **3.3, handshake:** `challenge`, `hello` over `T_hello`, `welcome` (with `unlock_seconds`), every `bye` code
  (`unknown_device`, `revoked`, `bad_signature`, `bad_version`, `replaced`, `busy` above 32 connections, `bad_code`,
  `too_large`), pre-auth refusal, 30 s to authenticate.
- **3.4, requests:** ids in `[A-Za-z0-9_-]{1,64}`; `idem` (same charset) on every call outside the read-only set,
  kept 10 minutes per device, the first answer replayed (a repeat arriving while the first still runs waits for
  it); Pebble's refusals passed through with their codes; the bridge's own codes; the 30 s answer timeout.
- **3.5 and C4, events:** every Pebble event forwarded unchanged except `native_export_pdf`; `seq`/`ts` per epoch;
  the 30 ms `token`/`reasoning` merge (seq assigned after it); a replay buffer of 5,000 events or 10 minutes
  (whichever is more); the 4 MB backpressure drop; `remote.pebble`, `remote.mac`, and `remote.devices` carrying the
  method's array (with `current` right for each phone, also on replay).
- **3.6 and C1, proofs and the unlock:** v0.3 `T_proof` (nonce and idem); the 60 s window and the unused id; C2: an
  accepted signature is remembered 120 s per device, keyed by its `r`, so its `(r, n-s)` twin, which also verifies,
  is refused too. An accepted proof unlocks the device (all its connections) for `unlock_seconds`. Outside C1's 14
  reads and S-05's `remote.lock`, a call without the unlock gets `unlock_required`. **S-05:** `remote.lock` ends the
  unlock at once, and so does the close of the device's last connection. `elevated` = the offered 3.6 methods, `remote.unlock`,
  and `setting:<key>` for the keys Pebble's own `settings_file.widening()` covers (`permissions`, `git_decisions`,
  `memory_enabled`, `memory_layers`, `notifications`). An unclassified key needs a proof (fail closed).
- **3.7, the allowlist:** `PHONE_ALLOWED = ALLOWED - PHONE_EXCLUDED` (the main window's list copied from `main.rs`,
  checked against the checkout by a test), offered as far as the simulated Pebble answers (79 methods, with v0.5's
  `remote.folders` and the nine opening methods); `new_chat`/`set_workspace` as "Proposal v0.5" says.
- **3.8:** every `remote.*` method, plus `remote.unlock` (`{unlocked_until, unlock_seconds}`), C3's
  `remote.screenshot` and v0.5's `remote.folders`. `remote.keep_awake` is on by default and needs no proof (R3).
- **v0.5:** `remote.folders` (the real home folder, or `--folders-root`; the protected list copied from Pebble's Shell
  sandbox, compared with the checkout by a test), the new-folder rule for `set_workspace` and `new_chat` (a proof, and a
  folder the listing would show), the nine opening methods (elevated, simulated, never opened), `terminal_propose`'s
  review card, and `attach_url` and `new_chat`'s workspace as Pebble does them.
- **v0.6:** `remote.folder_create` (a real folder in the home folder or the `--folders-root` tree, the name rules, one
  empty folder, elevated, a content-free log) and the ten minutes in which a folder a device made needs only the unlock
  for `set_workspace` and `new_chat` ("Proposal v0.6").
- **3.9 and 3.11 item 6, limits:** too-large requests (`res` when they parse with an id, else `bye`), too-large
  answers, 1 MB events (trimmed), 20/10 per second per device, content-free logs.
- **C3, screenshots:** two displays, 1512x982 and 2560x1440, each a generated test pattern (colour bars, a grey ramp,
  a checkerboard, a sage frame; the second mirrored), PNG written with zlib, made a JPEG by `sips` once, kept in
  memory. Never a real capture. The Mac's notice is a log line.
- **C6, LAN exposure:** at most 10 handshakes a minute per source address (loopback exempt unless
  `--limit-loopback`), answered `429` with `Retry-After: 60` before any WebSocket; private addresses only; the
  Bonjour instance named by the bridge id.
- **4.6:** revocation closes the phone's connection, refuses its key, and ends its unlock.

## What is simulated

A Pebble backend in memory with Pebble's method names, parameters, results, refusal sentences and event payloads,
read from the Pebble checkout (`backend/pebble/app.py` `state()`, `chat()`, `send()`, `stop()`, `approve()`,
`reject()`, `setting()`, `question_answer()`; `runner.py`; `controller.py`; `interaction.py`; `run_activity.py`;
`data_mirror.py`; `attachments.py`; `job_api.py`; `workshop.py`; `activity_kinds.py`; `src/types.ts`):

- **Four conversations:** a finished fix with an applied edit; "Tidy the test suite", waiting on a `command` card
  (`npm test`) with a shared Calculator window; "Plan the garden beds", waiting on a required question with a plan;
  "Weekly numbers", with two schedules (one paused).
- **Runs that stream:** `run` (`queued`, `running`, then the settled state with `elapsed`), `reasoning` deltas,
  `progress` with real tool names and their `activity` class, `token` pieces of 1 to 6 characters about 20 ms apart
  (so the 30 ms merge shows), `usage`, `complete`, `idle`; `activity` items as Pebble's timeline shapes them
  (context, tools, the model's reply), a `stream` commit per reply; `actions`, `question`, `plan`, `stopped`,
  `settings`, `model`, `toolbox`, `job`, `storage`.
- **What a `send` does depends on its words:** "test" proposes an `npm test` card (approve runs it in about 1.2 s and
  the run continues; reject continues without it); "which", "ask me" or "question" asks a question (answering or
  cancelling it continues the run); "slow" or "long" streams for about 12 s at `--speed 1` with a helper `agent` and
  a background `process` (to try Stop, Pause and guidance); anything else streams a short reply ("reply with the
  single word ok" gets `ok`). A `send` while that conversation's run works steers it (stored as a message, Pebble's
  rule); one in another conversation gets "One task can run at a time on this device." `/help` answers at once.
- **The P1 calls A's store makes:** Recently deleted (`storage_trash_chat`, `storage_restore_chat`, the elevated
  `storage_purge_chat`, `storage_summary`'s `recently_deleted`; a trashed conversation refuses `send` with code
  `trashed_conversation`); `attach_bytes` in base64 pieces (an `upload` token, byte offsets, up to 96,000
  characters a piece) and `attach_url`, `remove_source`, `send` with `source_ids`; schedules (`job_preview` with a
  fingerprint, the elevated `job_create` and `job_resume`, `job_preview_resume`, `job_pause`, `job_delete`);
  Toolbox (`toolbox_remove`, `toolbox_undo_remove`, `toolbox_decide`, each answering the listing); every setting key
  Pebble accepts, with its checks; `set_workspace` and `new_chat {workspace}` (a project in use, or a new folder as v0.5
  says; the folder must exist), `model_load`/`model_unload`, `screen_handoff_done`, `browser_status`/`browser_stop`,
  `artifact_get` (no artifacts yet).
- **v0.5:** `terminal_propose` makes a pending `command` card (never run: its approval answers a simulated result);
  `open_url`, `open_app`, `view_stage`, `artifact_view_open`, `browser_start`, `browser_open_tab`, `quiz_share` and
  `process_terminal` check their parameters and answer `{ok: true}`; `attach_url`'s fetch is a made-up source.
- **Not simulated:** artifacts and native views (C5's schema is to come), sub-agents beyond the one event, real jobs
  firing, browser and screen control (and anything the nine opening methods would change: `browser_status` stays
  "not running"), Pebble restarts (only the USR2 switch), the Mac's own notices (C7).

## Tests

```sh
python3 -I -B -m unittest discover -s bridge-mock -p 'test_*.py'     # from the repository root, about 65 s, 177 tests
```

- **ECDSA:** RFC 6979's P-256 vectors, `openssl` in both directions, high-s accepted, 11 known-bad and 9 malformed
  signatures refused, point validation.
- **The pin:** against `openssl`'s, state file modes, re-issue with the same key.
- **WebSocket:** RFC 6455's own examples, every length form, fragments with a ping between them, a UTF-8 character
  split across fragments, ten protocol errors and their close codes, the upgrade's checks.
- **The wire:** the link (IPv6 brackets, spaces as `%20`), the transcripts byte for byte, the v0.3 `T_proof` golden
  agreed with lane B, the id charset, private addresses, strict base64url.
- **Contract tables:** `ALLOWED - PHONE_EXCLUDED`, the elevated and unlock classes, the simulated methods; parity with
  the Pebble checkout when it is present (`PEBBLE_CHECKOUT`): `main.rs`'s `ALLOWED` and `NATIVE_ONLY`, and every key
  Pebble's `setting()` accepts classified, with each key `widening()` covers elevated (this test fails when Pebble gains
  an unclassified key).
  v0.5 adds the nine opening methods in both tables, `remote.folders` as a read that needs the unlock, and a parity
  test that reads the checkout's `shell_policy.py` as text (`ast`, nothing run) and compares the protected list.
- **Folders (v0.5):** the listing's exact shape, order and 500 cap, `is_project` for a folder and a worktree's file,
  hidden (dot and flag), protected, own-state and link folders left out, every refusal and its code (outside home,
  `..`, links, hidden and protected paths whether or not they exist, bad types, missing, unreadable), and a property
  test: walking the tree, every folder shown can be connected and nothing else can.
- **The bridge, v0.5:** which `set_workspace` and `new_chat` values need a proof, that a new folder gets the same
  `proof_required` whether it exists or not (and locked or not), that a proof connects only a listed folder, that a
  connected folder is then a known project, the nine opening methods (proof needed, nothing opened: `subprocess`,
  `os.system` and `webbrowser` are made to fail, and the log holds no URL, command or id), `terminal_propose`'s card, its
  `actions` event, its approval and its refusals, `attach_url` in Pebble's order, and the welcome's lists.
- **Links (v0.5):** a path that is itself a link (to a folder inside home, out of it, to a file, to nothing, to a
  link, below a folder, with a trailing slash, or a path below it) is `not_allowed` in `remote.folders`, and in
  `set_workspace` and `new_chat` even with a proof (and `proof_required` without one); none is listed; a
  `--folders-root` reached through a link is its real path only.
- **Names (v0.6):** the trim and every rule of the name of a new folder (accented, emoji and CJK names are kept; 255 bytes
  is the longest; a lone surrogate, a control character, a colon, a slash and a leading dot are refused), each with its
  words, none with a banned word.
- **Folders made (v0.6):** `Folders.create` in a temporary tree: one empty folder and exactly the entry the listing
  gives, the home folder and a trailing slash as parents, a folder inside a made folder, the trimmed name, every
  refusal with its code and words (bad name, outside home, `..`, links, hidden and protected parents, a parent that is
  not there or is a file, a name already there as a folder, a file and (on a case-insensitive disk) in another case, a
  name the listing would hide, a folder that cannot be written, a write that fails otherwise) leaving the disk exactly
  as it was, and the folder made inside the one that was checked even when a link has taken its place.
- **The bridge, v0.6:** a proof for `remote.folder_create` (plain: `proof_required`, locked or not, nothing made; the
  proof unlocks), an `idem` on it, the answer's shape, the refusals over the bridge, the log (the name, the parent and the
  tree never appear), two phones making one name once; and the ten minutes: a plain `set_workspace` and `new_chat` for the
  folder this device made, exactly that path only, not another device, not after ten minutes (nor just inside them), a
  locked phone still needing the unlock, a folder that is gone or has become a link refused, a removed device forgotten, at
  most 64 remembered.
- **X-1:** the formula against both vectors, with the hash written out again, zero padding kept, and every field
  changing the code; the watchdogs leaving a connection that waits for the person alone; what the phone sends while it
  waits being ignored; and, over the wire against the mock: the default wait of about 1.5 s and the `PAIRING_CODE=`
  line equal to the formula over that session's T_pair; `ask` mode (nothing but the challenge arrives before `y`, the
  same code on another connection is refused meanwhile, then `paired`; `n` is `bye` `bad_code` with words and a spent
  code and nothing stored; no answer within `--pair-confirm-timeout` is the same; a phone that leaves is not stored
  and the code stays spent); and conformance with `--expect-pair-refused` against `--pair-confirm refuse`.
- **S-05:** `remote.lock` as a read (no unlock, no proof, no idem, one device's alone, unlock again with a proof), and
  over the wire: the unlock ending with `remote.lock`, surviving a replaced connection, and ending with the last one.
- **Screenshots:** the PNG's chunks and CRCs; `sips` JPEGs of the right size, nothing left behind.
- **The bridge:** the 30 ms merge, the resume window, the watchdog, backpressure, proofs bound to the nonce and the
  idem, C2 (the twin included), the unlock window, the handshake limit, the per-phone devices event, C4's one
  exclusion; the card, question, stop and steer flows.
- **End to end:**
  - the mock on an ephemeral port with conformance against it, listing a temporary tree (no FAIL; every v0.5 row
    passes; the two C6 rows SKIP);
  - a new link on SIGUSR1, the same pin after a restart;
  - conformance FAILS a mock on v0.2 proofs (the checker discriminates);
  - an elevated `approve` of the waiting card and every P1 flow above over the wire;
  - the unlock lapsing (`--unlock-seconds 1`), the Screen Recording refusal, and the 429 at the eleventh handshake
    (`--limit-loopback`);
  - v0.5 over the wire: the listing (the mock's own state folder inside the tree stays out), a new folder with and
    without a proof, `new_chat` in it, `terminal_propose`'s card as an `actions` event, `attach_url`, `open_url`;
  - **the v0.5 rows discriminate:** run in this process against a bridge that follows the proposal (all pass) and against
    bridges that list hidden or protected folders, let a path outside home through, follow links, connect a new folder
    without a proof, forward `new_chat` as it is, open something without a proof, send a listing of the wrong shape (six
    ways), or skip the unlock: each fails its own row and no other; a bridge without `remote.folders` is judged by
    v0.3 alone;
  - **so do v0.6's:** run in this process against a bridge that follows the proposal (all three rows pass, and nothing
    is left in the tree or the folder above it) and against bridges that make a folder without a proof, do not keep the name
    rules (a hidden folder, a colon, a control character are made, found and removed), make a folder in the folder above
    home, give "already there" a code, answer another shape, do not remember what a device made, or remember more than
    that one folder: each fails its own row and no other; the rows are skipped with `--no-create-probe`, `--no-connect`,
    away from this Mac and outside the user's own home or a temporary tree; a bridge without `remote.folder_create` is
    judged by v0.5 alone, and one that offers it without `remote.folders` fails the welcome row; over the wire, against
    the mock as its own process: a folder made with a proof, listed, connected with the unlock alone;
  - **so do X-1's and S-05's:** a bridge that confirms by itself at once fails the timing row; one that pairs instead of
    refusing fails the refusal row; one whose `remote.lock` answers `{}` and does nothing, one without `remote.lock`, and
    one whose unlock outlives its last connection each fail their own S-05 row.

Lane B's own end-to-end test (`PEBBLE_MOCK_E2E=1 scripts/swift.sh test --filter MockBridgeE2ETests`) runs its real
client against this mock and passes on v0.3.

## Notes for implementers

- **The pin from an iOS key:** a P-256 SPKI is the fixed prefix `3059301306072a8648ce3d020106082a8648ce3d030107034200`
  followed by the 65-byte X9.63 point, so pin = base64url(SHA-256(prefix + `SecKeyCopyExternalRepresentation`)).
- **T_proof v0.3 golden** (agreed with lane B, 01:16 and 01:22): bid `b-1`, device `d-1`, epoch `e-1`, nonce `n-1`,
  id `r42`, idem `0f8fad5b-d9cb-469f-a165-70867728950e`, method `approve`, params_json `{"action_id":"a9","id":"c1"}`,
  ts `1761780000000`. Digest line `IjGkhgxEHL96SaH_YpvZ_QIRTIdaiepSsS2nStVZGXM`; SHA-256 of the transcript
  `d0e32872b7515632da3ffaa1059db00ad0ba78c80297ed5c495492479d70a19e`.
- **C2 keyed by `r`:** ECDSA signatures are malleable: `(r, n-s)` verifies whenever `(r, s)` does. A replay cache keyed
  on the signature's bytes misses the twin; keyed on `(device, r)` it does not.
- **ECDSA here is not constant time.** Verification touches only public data, so a bridge may reuse it; signing is for
  the checker's test keys only.
- **Signatures:** DER, as `SecKeyCreateSignature(.ecdsaSignatureMessageX962SHA256)` makes them; the signer hashes the
  transcript with SHA-256. The mock refuses non-minimal DER and accepts high-s.

## Contract issues

Resolved in v0.3 (section 3.11): `bye` `bad_code`; the request-id charset; `T_proof` bound to the connection and the
call; `idem` on every non-read; `setting:<key>` in `elevated`; too-large requests; unix ms; unnamed events forwarded.

Open, with the mock's behaviour in brackets (on docs/TEAM_BOARD.md too):

1. **Which calls are read-only (no `idem`) is not in the contract.** Lanes B and C agreed a list on the board (01:16):
   C1's 14 reads plus `model_profiles`, `screen_sessions`, `toolbox_list`, `toolbox_get`, `job_list`, `job_get`,
   `job_preview`, `job_preview_resume`, `goal_list`, `goal_get`, `notification_status`, `command_catalogue`,
   `storage_summary`, `browser_status`, `remote.screenshot`. Proposal: write it into 3.4. [As agreed.]
2. **The new wire forms are not in sections 3.3, 3.4 and 3.8 yet:** `bye` `too_large`; the refusal code
   `unlock_required`; `remote.unlock`'s result `{unlocked_until, unlock_seconds}`; `welcome.unlock_seconds`.
   [As listed.]
3. **C2 should say "keyed by the signature's `r`".** Keyed by its bytes, the `(r, n-s)` twin passes. [Keyed by `r`.]
4. **C6's limit and loopback.** One conformance run makes about 13 handshakes, so a bridge that also limits loopback
   fails its own checker. Proposal: loopback is exempt (it is this Mac), and a refused handshake is answered `429`
   with `Retry-After: 60` before any WebSocket. [As proposed.]
5. **C1's reads leave out reads the phone shows:** `model_profiles`, `toolbox_list`, `job_list`, `screen_sessions`,
   `storage_summary`... need the unlock. That is a choice, not a flaw; say it in C1 so the phone unlocks before it
   fills Control. [As C1 is written.]
6. **`setting:<key>` and direction.** Pebble's `widening()` is directional (turning memory off widens nothing), but
   `elevated` is per key. [Every change of an elevated key needs a proof.]
7. **Pebble's `job_resume` needs `job_preview_resume`'s fingerprint:** v0.2's 3.7 now lists both. Resolved.

Opened by lane C2 for proposal v0.5 (2026-10-30; also on docs/TEAM_BOARD.md):

8. **`new_chat {workspace}` as claude-w answered it ("forwarded as is") would be a way around Face ID.** With the unlock
   alone, a phone could connect any folder of home through `new_chat`, which `set_workspace` guards with a proof.
   [The mock gives `new_chat` the `set_workspace` rule; conformance row 27 fails a bridge that does not. If the rule is
   not wanted, drop that row's `new_chat` half.]
9. **`remote.folders` and `idem`.** It is read-only, so the mock takes it with or without one (C1's list leaves it out, so
   the phone's client sends one). [Either way.]
10. **What the nine opening methods answer.** The mock answers `{ok: true}`; Pebble answers `true` for `open_url`, a
    review card for `open_app`, and so on. A phone should not read these results. [`{ok: true}`, as the brief says.]
11. **"Hidden".** The mock hides a name that starts with a dot and macOS's hidden flag (so `~/Library`, which Pebble does
    not protect as a whole). Conformance only requires the dot. [Both.]
12. **A `path` below a hidden or protected folder, or a hidden or protected one that is not there,** is `not_allowed`, not
    "not found", so the answer says nothing about what exists. The proposal does not say. [As written.]
13. **The 500 cap is silent** and the cut keeps the first 500 by name; `set_workspace` accepts a listed folder even when
    the cap cut it off the listing. [As proposed.]
14. **X-1 and S-05 are in the mock now** (2026-10-30, lane C2), as claude-w specified them at 10:49. What the written
    specs leave open, and what the mock did:
    - **The wait for `paired`** can be two minutes. The mock does not run its 30 s authentication or 45 s idle timers
      for a connection that waits for the person; a bridge that does will drop the pairing. [As described.]
    - **The code is spent** when the signatures verify, before the person answers, so a second phone cannot race the
      first with the same link. A phone that leaves while the Mac waits is not stored. [As described.]
    - **`bye` words:** "Pairing wasn't confirmed on your Mac. Show a new pairing link there and try again." The
      contract's table has one `bad_code` sentence (an expired or used link); X-1 adds a second cause. [Both.]
    - **The conformance checker cannot see the Mac's code.** It prints its own and a person compares; the timing row
      (`paired` at least 1 s after `pair`) is the only test that a bridge waited. [As described.]
    - **The phone's `readTimeout` (10 s) is shorter than the wait.** `LiveClient.pair` would give up before a person
      confirms. [Not the mock's to change.]
    - **After S-05, a reconnect locks the device.** Every network change that drops the last connection means Face ID
      again before the next call that acts. [As specified: "or end a device's unlock when its last connection closes".]
    - **`remote.lock` joins C1's reads (15 now):** the phone's `RemoteContract.readMethods` has 14. [To add there.]

Opened by lane F for proposal v0.6 (2026-10-30; also on docs/TEAM_BOARD.md):

15. **A folder the listing would hide.** `secrets`, `credentials`, `*.key` and the other protected names are not shown by
    `remote.folders`, and a folder with such a name could never be listed, opened or connected. The proposal's name rules
    do not mention them. [The mock refuses such a name up front (`bad_request`, "Pebble keeps folders with that name off
    your iPhone. Choose another name."). Conformance does not check it: say if the real bridge should.]
16. **`parent: null`.** `remote.folders` takes `path: null` for home. [`remote.folder_create` needs a string: the phone
    always sends the listing's `path`. `null` or a missing parent is `bad_request`.]
17. **Trimming.** "1 to 255 bytes of UTF-8, trimmed." does not say who trims. [Both: the phone trims before it sends, and the
    mock trims what it gets (every Unicode separator, the tab, the line breaks and U+0085). Conformance never sends a
    padded name, so a bridge that refuses one passes.]
18. **A name already there is words and no code** ("A folder with that name is already there."), as the proposal says,
    although the name list names it among the names "not allowed" (which are `bad_request`). A file with that name counts
    too, so the answer tells a phone that has a proof that something is there. [As the proposal; conformance requires
    words and no code.]
19. **The ten minutes count from the answer,** per device and per exact path, and survive a lock (the person unlocks again;
    the memory stays). They end with the removal of the device, not with the connection. [As described in "Proposal v0.6".]
