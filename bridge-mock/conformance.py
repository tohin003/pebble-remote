#!/usr/bin/env python3
"""Pebble Remote conformance checker: plays the iPhone against any bridge and judges it against contract v0.3, X-1
and S-05 (claude-w's 10:49 answers), proposal v0.5 when the bridge offers `remote.folders`, and proposal v0.6 when it
offers `remote.folder_create`.

    python3 -I bridge-mock/conformance.py --link '<pairing link>'

The link must be fresh (pairing consumes it). The checker pairs a software "phone" (two P-256 keys made here, standing
in for the Secure Enclave's `device` and `approve` keys). X-1: the bridge answers `pair` only after the person
confirms a six-digit code on the Mac, so the checker prints the code it computes ("pairing code 123456: confirm on
the Mac") and waits for the person (--pair-wait, 130 s); --expect-pair-refused checks the refusal instead. Then it
checks the transport, pairing, the handshake, the
unlock (C1), the allowlist, Face ID proofs (v0.3 T_proof, C2), setting keys, request ids, idempotency, resume, events
(C4), one connection per device, the limits, screenshots (C3), revocation and LAN exposure (C6). S-05: `remote.lock`,
and an unlock that ends with the device's last connection. With v0.5 it also checks `remote.folders`, how a new folder
is connected (`set_workspace`, `new_chat`), the rule for links, and that opening things on the Mac needs a proof. With
v0.6 it checks that `remote.folder_create` makes one empty folder with a proof, refuses a bad name or parent, and that a
folder the phone just made connects with the unlock alone. Every check uses ordinary contract calls only (but for the
links and folders below), so it runs the same against the mock and the real bridge.

What it leaves behind on the Mac: one conversation it created (first message "Pebble Remote conformance check: ...",
one short reply). The `permissions` setting it writes is the value it read. It takes one screenshot (kept in memory
only, never written; skip it with --no-screenshot). With v0.5 it connects one folder of the home folder to that
conversation with a proof and takes it off again (skip it with --no-connect), and makes a few empty conversations.
On loopback it also makes two links in the home folder to try the link rule, and removes them at once (skip it with
--no-link-probe). With v0.6, on loopback only, it asks the bridge for a few empty folders in the home folder, named
pebble-remote-conformance-<random>-..., and removes each one at once (skip it with --no-create-probe). It never opens
anything on the Mac: calls that would are sent without a proof, so a correct bridge refuses them. At the end it removes its own paired device (unless --keep-device). Run it while Pebble is idle: one
check sends a message.

Exit code 0 only when no check fails (SKIP rows do not fail). Contract: the bridge contract,
sections 3 (with 3.11) and 4, and claude-w's C1 to C7 and the answers of 10:49 and 10:53 in section 7. Python standard
library only.
"""

import argparse
import asyncio
import base64
import contextlib
import json
import os
import posixpath
import ssl
import sys
import tempfile
import time
import uuid

sys.dont_write_bytecode = True  # no __pycache__ in the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import remote_wire as wire  # noqa: E402

# A core every bridge offers, and calls the phone must never reach. Each refused call carries a parameter no Pebble
# route takes, so even a bridge that wrongly relayed one would make Pebble refuse it, with nothing done.
CORE = {'state', 'get_chat', 'new_chat', 'send', 'cancel', 'setting'}
NEVER = ['open_url', 'open_app', 'attach', 'set_model', 'model_remove', 'chatgpt_start', 'chatgpt_sign_out',
         'plan_credential_save', 'connector_start', 'extension_add', 'terminal_propose', 'quiz_share', 'storage_reveal',
         'lifecycle_event', 'export_pdf_attach', 'no_such_method']
# Folders a try is never made in: macOS asks the person before an app reads inside them.
AVOID = ('Desktop', 'Documents', 'Downloads', 'Library', 'Movies', 'Music', 'Pictures', 'Public')
BRIDGE_CODES = {'not_allowed', 'proof_required', 'bad_proof', 'too_large', 'rate_limited', 'pebble_offline',
                'timeout', 'bad_request', 'unlock_required'}
SETTLED = {'completed', 'failed', 'stopped', 'cancelled', 'interrupted', 'paused', 'budget_exhausted',
           'verification_required', 'needs_reconciliation'}
MESSAGE = 'Pebble Remote conformance check: reply with the single word ok.'
LONG_SIDE = 2560


class CheckFailed(Exception):
    pass


class Skipped(Exception):
    pass


def require(condition, words):
    if not condition:
        raise CheckFailed(words)


def describe(frame):
    """A frame in a few content-free words, for failure messages."""
    if frame is None:
        return 'nothing'
    if not isinstance(frame, dict):
        return 'a non-object frame'
    kind = frame.get('t')
    if kind == 'res':
        return 'res ok=%s code=%s' % (frame.get('ok'), frame.get('code'))
    if kind == 'bye':
        return 'bye code=%s' % frame.get('code')
    if kind == 'evt':
        return 'evt %s seq=%s' % (frame.get('event'), frame.get('seq'))
    return str(kind)


def is_ms(value, around=None, slack_ms=600000):
    """A whole number of unix milliseconds (after 2001), near `around` when given."""
    if type(value) is not int or value < 10 ** 12:
        return False
    return around is None or abs(value - around) <= slack_ms


def new_idem():
    return str(uuid.uuid4())


class Pacer:
    """Keeps the checker under the bridge's rate limit (20 in a burst, 10 a second) except where it tests that limit."""

    def __init__(self, burst=12, rate=8.0):
        self.burst, self.rate = burst, rate
        self.tokens, self.at = float(burst), time.monotonic()

    async def take(self):
        while True:
            now = time.monotonic()
            self.tokens = min(self.burst, self.tokens + (now - self.at) * self.rate)
            self.at = now
            if self.tokens >= 1:
                self.tokens -= 1
                return
            await asyncio.sleep((1 - self.tokens) / self.rate)


class Peer:
    """One phone connection: TLS 1.3 with the link's pin checked before anything is sent, the WebSocket upgrade, and a
    reader task that files every frame in arrival order."""

    count = 0

    def __init__(self, checker, label):
        self.checker, self.label = checker, label
        self.frames, self.arrived, self.closed = [], [], False   # arrived[i]: when frames[i] came (monotonic)
        self.pair_seconds = None  # how long the bridge took to answer `pair`
        self.changed = asyncio.Event()
        self.ws = self.task = None
        self.challenge = self.welcome = None
        self.tls_version = self.pin = None
        self.headers = {}

    @property
    def nonce(self):
        return (self.challenge or {}).get('nonce', '')

    async def connect(self, subprotocol=wire.WS_SUBPROTOCOL):
        host, port = self.checker.endpoint
        timeout = self.checker.timeout
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE  # trust comes from the pin below, never from a CA
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(host, port, ssl=context, ssl_handshake_timeout=timeout,
                                        limit=1 << 16), timeout)
        except ssl.SSLError as exc:
            raise CheckFailed('the TLS 1.3 handshake failed (%s)' % exc.reason) from None
        except (OSError, asyncio.TimeoutError, TimeoutError) as exc:
            raise CheckFailed('could not connect to %s (%s)' % (wire.format_endpoint(host, port),
                                                               type(exc).__name__)) from None
        ssl_object = writer.get_extra_info('ssl_object')
        self.tls_version = ssl_object.version()
        der = ssl_object.getpeercert(binary_form=True)
        self.pin = wire.certificate_pin(der) if der else None
        if self.pin != self.checker.link['pin']:
            writer.close()
            raise CheckFailed('the certificate key does not match the pin in the link')
        try:
            self.ws, self.headers = await wire.client_handshake(reader, writer, wire.format_endpoint(host, port),
                                                                subprotocol=subprotocol, timeout=timeout)
        except wire.HandshakeRefused as exc:
            writer.close()
            raise CheckFailed('the WebSocket upgrade was refused: ' + exc.status) from None
        except (asyncio.IncompleteReadError, asyncio.TimeoutError, TimeoutError, ConnectionError, ValueError):
            writer.close()
            raise CheckFailed('the WebSocket upgrade got no proper answer') from None
        self.task = asyncio.create_task(self._read())
        found = await self.wait(lambda f: True, timeout)
        require(found is not None, 'no challenge after the WebSocket opened')
        self.challenge = found[1]
        return self.challenge

    async def _read(self):
        while True:
            message = await self.ws.recv()
            if message is None:
                break
            if isinstance(message, bytes):
                frame = {'t': '<binary>'}
            else:
                try:
                    frame = json.loads(message)
                except ValueError:
                    frame = {'t': '<not json>'}
            if not isinstance(frame, dict):
                frame = {'t': '<not an object>'}
            self.frames.append(frame)
            self.arrived.append(time.monotonic())
            if self.checker.verbose:
                print('    %s <- %s' % (self.label, describe(frame)), file=sys.stderr)
            self.changed.set()
        self.closed = True
        self.changed.set()

    async def wait(self, predicate, timeout, start=0):
        """The first frame from index `start` on that matches: (index, frame), or None on timeout or close."""
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        index = start
        while True:
            while index < len(self.frames):
                if predicate(self.frames[index]):
                    return index, self.frames[index]
                index += 1
            if self.closed:
                return None
            remaining = deadline - loop.time()
            if remaining <= 0:
                return None
            self.changed.clear()
            try:
                await asyncio.wait_for(self.changed.wait(), remaining)
            except (asyncio.TimeoutError, TimeoutError):
                pass

    async def wait_closed(self, timeout):
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while not self.closed and loop.time() < deadline:
            self.changed.clear()
            try:
                await asyncio.wait_for(self.changed.wait(), deadline - loop.time())
            except (asyncio.TimeoutError, TimeoutError):
                pass
        return self.closed

    async def send(self, frame):
        await self.ws.send_text(json.dumps(frame, separators=(',', ':')))

    def next_id(self):
        Peer.count += 1
        return 'c%d' % Peer.count

    async def request(self, method, params=None, *, idem=None, request_id=None, pace=True):
        """A plain request (params as an object). Pass idem for anything outside the read-only calls."""
        request_id = request_id or self.next_id()
        frame = {'t': 'req', 'id': request_id, 'method': method, 'params': {} if params is None else params}
        if idem is not None:
            frame['idem'] = idem
        return await self.exchange(frame, pace=pace)

    async def act(self, method, params=None):
        """A plain request that changes something: always with a fresh idem (v0.3 item 4)."""
        return await self.request(method, params, idem=new_idem())

    async def exchange(self, frame, pace=True, any_id=False):
        if pace:
            await self.checker.pacer.take()
        start = len(self.frames)  # an answer that came before this send (an earlier use of the id) does not count
        await self.send(frame)
        found = await self.wait(lambda f: f.get('t') == 'res' and (f.get('id') == frame['id'] or
                                                                   (any_id and f.get('id') is None)),
                                self.checker.timeout, start)
        require(found is not None, 'no answer to %s (%s)' % (frame.get('method'),
                                                          'connection closed' if self.closed else 'timed out'))
        return found[1]

    def elevated_frame(self, method, params, *, request_id=None, idem=None, key=None, ts=None, epoch=None, nonce=None,
                       sign_method=None, sign_idem=None, params_json=None, signed_json=None, v02=False):
        """An elevated request (section 3.6, v0.3): params as a JSON string, and a proof by the approve key over
        T_proof, which binds bid, device, epoch, this connection's nonce, the id, the idem, the method, the params'
        digest and ts. The keyword arguments make the bad variants."""
        phone = self.checker.phone
        request_id = request_id or self.next_id()
        idem = idem or new_idem()
        text = params_json if params_json is not None else json.dumps(params, separators=(',', ':'))
        signed = signed_json if signed_json is not None else text
        ts = wire.now_ms() if ts is None else ts
        bid = self.checker.link['bid']
        if v02:
            transcript = wire.t_proof_v02(bid, phone.device_id, epoch or self.checker.epoch, request_id,
                                          sign_method or method, signed, ts)
        else:
            transcript = wire.t_proof(bid, phone.device_id, epoch or self.checker.epoch, nonce or self.nonce,
                                      request_id, sign_idem or idem, sign_method or method, signed, ts)
        signature = (key or phone.approve_key).sign(transcript)
        return {'t': 'req', 'id': request_id, 'method': method, 'params_json': text, 'idem': idem,
                'proof': {'ts': ts, 'sig': wire.b64u(signature)}}

    async def hello(self, device_id=None, key=None, resume=None, nonce=None):
        phone = self.checker.phone
        device_id = device_id or phone.device_id
        transcript = wire.t_hello(self.checker.link['bid'], device_id, nonce or self.nonce, self.checker.link['pin'])
        signature = (key or phone.device_key).sign(transcript)
        start = len(self.frames)
        await self.send({'t': 'hello', 'v': 1, 'device_id': device_id, 'sig': wire.b64u(signature),
                         'resume': resume, 'app': 'conformance 0.5'})
        found = await self.wait(lambda f: f.get('t') in ('welcome', 'bye'), self.checker.timeout, start)
        if found and found[1].get('t') == 'welcome':
            self.welcome = found[1]
        return found[1] if found else None

    async def pair(self, code, device_key, approve_key, wait=None, announce=False):
        """`pair`, then the answer. With X-1 the answer comes after the person confirms the code on the Mac, so `wait`
        (default: the checker's usual timeout) is long where a person is involved; `announce` prints the six digits
        that the Mac must show, for that person to compare."""
        link = self.checker.link
        transcript = wire.t_pair(link['bid'], self.nonce, link['pin'], code, device_key.x963_b64u,
                                 approve_key.x963_b64u)
        start = len(self.frames)
        sas = wire.sas_code(transcript)
        if announce:
            self.checker.pair_sas = sas
            print('    pairing code %s: confirm on the Mac (the code the Mac shows must be the same)' % sas, flush=True)
        sent = time.monotonic()
        await self.send({'t': 'pair', 'v': 1, 'code': code,
                         'device': {'name': 'Pebble Remote conformance', 'model': 'conformance', 'os': 'Python',
                                    'app': 'conformance 0.5'},
                         'device_key': device_key.x963_b64u, 'approve_key': approve_key.x963_b64u,
                         'sig': wire.b64u(device_key.sign(transcript)),
                         'approve_sig': wire.b64u(approve_key.sign(transcript))})
        found = await self.wait(lambda f: f.get('t') in ('paired', 'bye'), wait or self.checker.timeout, start)
        if found is None:
            return None, None
        self.pair_seconds = self.arrived[found[0]] - sent
        if found[1].get('t') == 'bye':
            return found[1], None
        welcome = await self.wait(lambda f: f.get('t') in ('welcome', 'bye'), self.checker.timeout, found[0] + 1)
        if welcome and welcome[1].get('t') == 'welcome':
            self.welcome = welcome[1]
        return found[1], welcome[1] if welcome else None

    def events(self):
        return [f for f in self.frames if f.get('t') == 'evt']

    def last_seq(self, default):
        seqs = [f['seq'] for f in self.events() if type(f.get('seq')) is int]
        return max(seqs) if seqs else default

    async def close(self):
        if self.ws is not None and not self.closed:
            try:
                await self.ws.close(wire.CLOSE_NORMAL, 'done')
            except (ConnectionError, OSError):
                pass
        if self.task is not None:
            try:
                await asyncio.wait_for(self.task, 3)
            except (asyncio.TimeoutError, TimeoutError, asyncio.CancelledError):
                self.task.cancel()


class Phone:
    """The paired identity: a device key (signs challenges) and an approve key (signs elevated calls)."""

    def __init__(self):
        self.device_key, self.approve_key = wire.SigningKey(), wire.SigningKey()
        self.device_id = None


class Checker:
    def __init__(self, link, endpoint=None, timeout=10.0, run_timeout=120.0, verbose=False, keep_device=False,
                 screenshot=True, bonjour=False, connect=True, pair_wait=130.0, expect_pair_refused=False,
                 link_probe=True, create_probe=True):
        self.link = wire.parse_pairing_link(link)
        self.endpoint = endpoint
        self.timeout, self.run_timeout = timeout, run_timeout
        self.verbose, self.keep_device = verbose, keep_device
        self.screenshot, self.bonjour, self.connect = screenshot, bonjour, connect
        self.pair_wait, self.expect_pair_refused, self.link_probe = pair_wait, expect_pair_refused, link_probe
        self.create_probe = create_probe   # v0.6: ask for empty folders in the home folder (loopback only), then remove them
        self.pair_sas = self.pair_seconds = None   # X-1: the code the Mac must show, and how long `paired` took
        self.phone = Phone()
        self.pacer = Pacer()
        self.results = []
        self.epoch = None
        self.peers = []
        self.state = None
        self.status = {}
        self.chat_id = None
        self.permissions = None
        self.methods, self.elevated, self.limits, self.unlock_seconds = set(), set(), {}, None
        self.unlock_frame = self.unlocked_until = None   # the accepted remote.unlock frame, replayed for C2
        self.new_chat_idem = self.new_chat_answer = None
        self.device_row = {}
        self.connections = []         # when not on loopback: times of connection attempts (C6 pacing)
        self.plain_key = None         # a setting key that needs no proof, with its current value
        self.main_peer = None         # the connection pairing ended on
        self.adopted = None           # (peer, keys, paired, welcome) when a pair with a bad signature was accepted
        self.v05 = False              # the bridge offers remote.folders: proposal v0.5 applies
        self.v06 = False              # the bridge offers remote.folder_create: proposal v0.6 applies
        self.folder_home = self.folder_listing = self.folder_child = None   # from the listing row

    @property
    def loopback(self):
        return self.endpoint is not None and (self.endpoint[0] == 'localhost' or
                                              wire.address_kind(self.endpoint[0]) == 'loopback')

    # -- bookkeeping --------------------------------------------------------------------------------------------------

    def record(self, name, ok, detail='', started=None):
        ms = (time.monotonic() - started) * 1000 if started is not None else None
        self.results.append({'name': name, 'ok': ok, 'skipped': ok is None, 'detail': detail, 'ms': ms})
        timing = ('%6.0f ms' % ms) if ms is not None else '         '
        label = 'SKIP' if ok is None else 'PASS' if ok else 'FAIL'
        print('  %s  %-66s %s  %s' % (label, name, timing, detail), flush=True)

    async def check(self, name, function, *args):
        started = time.monotonic()
        try:
            detail = await function(*args)
            self.record(name, True, detail or '', started)
            return True
        except Skipped as exc:
            self.record(name, None, str(exc))
            return True
        except CheckFailed as exc:
            self.record(name, False, str(exc), started)
        except Exception as exc:  # a broken bridge must give a FAIL row, not a traceback
            self.record(name, False, 'unexpected %s: %s' % (type(exc).__name__, exc), started)
        return False

    def skip(self, names, why):
        for name in names:
            self.record(name, False, 'not run: ' + why)

    async def pace_connections(self):
        """C6 limits handshakes to 10 a minute per source address on the LAN: keep the run under it (9 a minute)."""
        if self.loopback:
            return
        now = time.monotonic()
        self.connections = [t for t in self.connections if now - t < 61]
        if len(self.connections) >= 9:
            wait = 61 - (now - self.connections[0])
            print('  (pacing connections for C6: waiting %.0f s)' % wait, flush=True)
            await asyncio.sleep(wait)
        self.connections.append(time.monotonic())

    async def peer(self, label):
        await self.pace_connections()
        peer = Peer(self, label)
        self.peers.append(peer)
        await peer.connect()
        return peer

    async def choose_endpoint(self):
        if self.endpoint:
            return
        last = None
        for host, port in self.link['endpoints']:
            try:
                reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), 3)
                writer.close()
                self.endpoint = (host, port)
                if not self.loopback:
                    self.connections.append(time.monotonic())
                return
            except (OSError, asyncio.TimeoutError, TimeoutError) as exc:
                last = exc
        raise CheckFailed('no endpoint in the link answered (%s)' % type(last).__name__)

    # -- the run ------------------------------------------------------------------------------------------------------

    ROWS = [
        'welcome fields (v0.3: unlock_seconds, elevated, setting:<key>)',
        'the code cannot be used twice (bye bad_code)',
        'a bad hello signature is refused',
        'C1: reads work before the unlock',
        'C6: private endpoints only (the link, remote.status)',
        'C1: acting before the unlock gets unlock_required',
        'elevated without a proof gets proof_required',
        'a bad proof gets bad_proof (v0.3 T_proof: nonce, idem)',
        'C1: remote.unlock with a proof unlocks; then acting works',
        'a good proof works; reusing its request id gets bad_proof',
        'a call outside the allowlist gets not_allowed',
        'setting:<key> entries need a proof; other keys do not',
        'a setting key cannot dodge the proof (twice, not a string, respelled)',
        'request ids outside [A-Za-z0-9_-]{1,64} get bad_request',
        'idem: a repeat returns the first answer; acting without one gets bad_request',
        'resume replays missed events in order; a send repeat acts once',
        'C2: a proof replayed on another connection gets bad_proof',
        'events: shape, order, batching; C4: activity is forwarded',
        'v0.3 item 7: bridge times are unix ms; remote.devices event',
        'a stale epoch gets resumed:false',
        'a second connection replaces the first (bye replaced)',
        'too large: a parsable request gets res too_large',
        'WebSocket: ping answered, fragmented request reassembled',
        'C3: remote.screenshot gives JPEGs, long side at most 2560',
        'a burst above the rate limit gets rate_limited',
        'too large: an unreadable frame gets bye too_large',
        'an unknown device is refused',
        'requests nested 20,000 and 300,000 deep leave the bridge serving',
        'revoking the device ends it and refuses its key',
        'C6: at most 10 handshakes a minute from one address',
        'C6: the Bonjour instance is named by the bridge id',
    ]

    # Proposal v0.5 (the iOS side's 2026-10-30 10:50, accepted by claude-w at 10:53). These rows run when welcome.methods
    # includes remote.folders; the first one runs while the device is still locked.
    V05_LOCKED = 'v0.5: remote.folders needs the unlock (unlock_required)'
    V05_LISTING = 'v0.5: remote.folders lists home (shape, order, at most 500), goes down and up'
    V05_OUTSIDE = 'v0.5: remote.folders refuses places outside home (not_allowed)'
    V05_PRIVATE = 'v0.5: hidden and protected folders are left out and refused'
    V05_LINKS = 'v0.5: a path that is a link, or resolves outside home, gets not_allowed (remote.folders, set_workspace)'
    V05_WORKSPACE = 'v0.5: set_workspace: a new folder needs a proof; null and a project in use do not'
    V05_NEW_CHAT = 'v0.5: new_chat in a new folder needs a proof; a project in use is kept'
    V05_OPEN = 'v0.5: opening things on the Mac is elevated (each of the nine needs a proof)'
    V05_ROWS = [V05_LISTING, V05_OUTSIDE, V05_PRIVATE, V05_LINKS, V05_WORKSPACE, V05_NEW_CHAT, V05_OPEN]

    # Proposal v0.6 (the iOS side's 2026-10-30 15:14): a new folder, made from the phone. These rows run when welcome.methods
    # includes remote.folder_create, after the v0.5 rows. Each makes its own folders in the home folder, on loopback only,
    # and removes them again.
    V06_CREATE = 'v0.6: remote.folder_create needs a proof and makes one empty folder that the listing shows'
    V06_REFUSALS = 'v0.6: remote.folder_create refuses a bad name or parent, and a name already there'
    V06_CONNECT = 'v0.6: a folder this device just made connects with the unlock alone (set_workspace, new_chat)'
    V06_ROWS = [V06_CREATE, V06_REFUSALS, V06_CONNECT]

    # X-1 (claude-w's 10:49 answer, item 3): the person confirms each pairing on the Mac. These rows follow the pairing row;
    # with --expect-pair-refused the run is X1_REFUSED and X1_SPENT instead.
    X1_FORMULA = 'X-1: the six-digit code (the formula against the fixed T_pair vectors; this pairing\'s code)'
    X1_CONFIRMED = 'X-1: paired comes only after the person confirms on the Mac, not at once'
    X1_REFUSED = 'X-1: a pairing the person cancels (or leaves unanswered) gets bye bad_code'
    X1_SPENT = 'X-1: the pairing code is spent after a refusal (bye bad_code)'
    X1_ROWS = [X1_FORMULA, X1_CONFIRMED]
    MIN_CONFIRM_SECONDS = 1.0   # a person cannot read two codes and answer faster; a bridge that confirms by itself can

    # S-05 (claude-w's 10:49 answer, item 4): remote.lock, and an unlock that ends with the device's last connection.
    S05_LOCK = 'S-05: remote.lock ends the unlock at once (a read: {} to {})'
    S05_LAST = "S-05: the unlock ends when the device's last connection closes"

    def v05_rows(self):
        return [self.V05_LOCKED] + self.V05_ROWS if self.v05 else []

    def v06_rows(self):
        return self.V06_ROWS if self.v06 else []

    async def run(self):
        print('Pebble Remote conformance (contract v0.3, X-1 and S-05, proposal v0.5 when the bridge offers '
              'remote.folders, and v0.6 when it offers remote.folder_create)')
        try:
            await self.choose_endpoint()
        except CheckFailed as exc:
            self.record('transport: TLS 1.3, the pinned key, the subprotocol', False, str(exc))
            return False
        print('  bridge %s at %s\n' % (self.link['bid'], wire.format_endpoint(*self.endpoint)))
        try:
            await (self._run_refused() if self.expect_pair_refused else self._run())
        finally:
            for peer in self.peers:
                await peer.close()
        failed = sum(1 for r in self.results if r['ok'] is False)
        passed = sum(1 for r in self.results if r['ok'] is True)
        skipped = sum(1 for r in self.results if r['ok'] is None)
        print('\nRESULT: %d/%d checks passed%s' % (passed, passed + failed,
                                                    ', %d skipped' % skipped if skipped else ''))
        return failed == 0

    async def _run(self):
        rows = self.ROWS
        first = None
        if await self.check('transport: TLS 1.3, the pinned key, the subprotocol', self.c_transport):
            first = self.peers[-1]
        if first is None:
            self.skip(['challenge format', 'frames before hello or pair get no answer'], 'no connection')
        else:
            await self.check('challenge format', self.c_challenge, first)
            await self.check('frames before hello or pair get no answer', self.c_preauth, first)
        await self.check('a wrong pairing code gets bye bad_code', self.c_wrong_code)
        await self.check('the right code with a bad signature gets bye bad_signature', self.c_pair_bad_signature)
        main = None
        if await self.check('pairing works (paired, then welcome)', self.c_pair):
            main = self.main_peer
        if main is None:
            self.skip(self.X1_ROWS + rows + [self.S05_LOCK, self.S05_LAST], 'pairing failed')
            return
        await self.check(self.X1_FORMULA, self.c_sas_formula)
        await self.check(self.X1_CONFIRMED, self.c_pair_confirmed)
        await self.check(rows[0], self.c_welcome, main)
        await self.check(rows[1], self.c_code_reuse)
        await self.check(rows[2], self.c_bad_hello, main)
        if not await self.check(rows[3], self.c_reads, main):
            self.skip(rows[4:] + [self.S05_LOCK, self.S05_LAST] + self.v05_rows() + self.v06_rows(), 'the reads failed')
            return
        steps = list(zip(rows[4:15], (self.c_private_endpoints, self.c_locked, self.c_proof_required,
                                      self.c_bad_proof, self.c_unlock, self.c_good_proof, self.c_not_allowed,
                                      self.c_setting_keys, self.c_setting_smuggling, self.c_request_ids,
                                      self.c_idem)))
        if self.v05:
            steps.insert(2, (self.V05_LOCKED, self.c_folders_locked))  # right after the locked row: still locked
        for name, function in steps:
            await self.check(name, function, main)
        if self.chat_id is None:
            self.skip(rows[15:] + [self.S05_LOCK, self.S05_LAST] + (self.V05_ROWS if self.v05 else []) + self.v06_rows(),
                      'no conversation (the unlock or new_chat failed)')
            return
        await self.check(self.S05_LOCK, self.c_lock, main)
        await self.run_v05(main)
        await self.run_v06(main)
        resumed = {}
        await self.check(rows[15], self.c_resume, main, resumed)
        if resumed.get('peer') is None:
            self.skip(rows[16:] + [self.S05_LAST], 'resume failed')
            return
        await self.check(rows[16], self.c_replay, resumed['peer'])
        await self.check(rows[17], self.c_events, resumed)
        await self.check(rows[18], self.c_times, main)
        replacing = {}
        await self.check(rows[19], self.c_stale_epoch, replacing)
        current = replacing.get('peer')
        if current is None:
            self.skip(rows[20:] + [self.S05_LAST], 'no connection after the stale-epoch hello')
            return
        await self.check(rows[20], self.c_replaced, resumed['peer'], current)
        await self.check(rows[21], self.c_too_large, current)
        await self.check(rows[22], self.c_websocket, current)
        await self.check(rows[23], self.c_screenshot, current)
        await self.check(rows[24], self.c_rate_limit, current)
        await self.check(rows[25], self.c_unreadable, current)
        await self.check(rows[26], self.c_unknown_device)
        await self.check(rows[27], self.c_deep_request)
        await self.check(self.S05_LAST, self.c_last_connection)
        if self.keep_device:
            self.record(rows[28], None, '--keep-device')
        else:
            await self.check(rows[28], self.c_revoke)
        await self.check(rows[29], self.c_handshake_limit)
        await self.check(rows[30], self.c_bonjour)

    # -- checks: transport, pairing, handshake ------------------------------------------------------------------------

    async def c_transport(self):
        peer = await self.peer('A')
        require(peer.tls_version == 'TLSv1.3', 'negotiated ' + str(peer.tls_version))
        protocols = [p.strip() for v in peer.headers.get('sec-websocket-protocol', []) for p in v.split(',')]
        require(protocols == [wire.WS_SUBPROTOCOL], 'the bridge did not choose subprotocol ' + wire.WS_SUBPROTOCOL)
        return 'pin ' + peer.pin[:10] + '...'

    async def c_challenge(self, peer):
        challenge = peer.challenge
        require(challenge.get('t') == 'challenge', 'the first frame was ' + describe(challenge))
        require(challenge.get('v') == 1, 'v is not 1')
        require(challenge.get('bid') == self.link['bid'], 'bid differs from the link')
        try:
            nonce = wire.b64u_decode(challenge.get('nonce'))
        except ValueError:
            raise CheckFailed('nonce is not base64url without padding') from None
        require(len(nonce) == 32, 'nonce is %d bytes, not 32' % len(nonce))
        require(is_ms(challenge.get('time'), wire.now_ms()), 'time is not the Mac clock in unix ms')
        other = await self.peer('A2')
        require(other.nonce != peer.nonce, 'two connections got the same nonce')
        await other.close()
        return ''

    async def c_preauth(self, peer):
        start = len(peer.frames)
        await peer.send({'t': 'req', 'id': 'before-hello', 'method': 'state', 'params': {}})
        found = await peer.wait(lambda f: f.get('t') == 'res', 2.5, start)
        require(found is None, 'the bridge answered a request before authentication: ' + describe(found and found[1]))
        await peer.wait_closed(1.0)
        return 'connection closed' if peer.closed else 'ignored'

    async def c_wrong_code(self):
        peer = await self.peer('B')
        paired, _ = await peer.pair(wire.b64u(os.urandom(16)), wire.SigningKey(), wire.SigningKey())
        require(paired is not None and paired.get('t') == 'bye' and paired.get('code') == 'bad_code',
                'a random code got ' + describe(paired))
        require(isinstance(paired.get('error'), str) and paired['error'], 'bye has no words for the person')
        require(await peer.wait_closed(3), 'the connection stayed open after bye')
        return ''

    async def c_pair_bad_signature(self):
        """3.2 step 2: the right code with a pair whose approve_sig is not by the approve key it names is refused. A
        refused pair counts as one of the code's five tries and leaves the code usable, so pairing follows. (If a
        bridge pairs it anyway, the run carries on with that pairing: the checker holds both keys.)"""
        peer = await self.peer('B2')
        device_key, approve_key = wire.SigningKey(), wire.SigningKey()
        link = self.link
        transcript = wire.t_pair(link['bid'], peer.nonce, link['pin'], link['code'], device_key.x963_b64u,
                                 approve_key.x963_b64u)
        start = len(peer.frames)
        await peer.send({'t': 'pair', 'v': 1, 'code': link['code'],
                         'device': {'name': 'Pebble Remote conformance', 'model': 'conformance', 'os': 'Python',
                                    'app': 'conformance 0.5'},
                         'device_key': device_key.x963_b64u, 'approve_key': approve_key.x963_b64u,
                         'sig': wire.b64u(device_key.sign(transcript)),
                         'approve_sig': wire.b64u(device_key.sign(transcript))})  # by the device key: no proof
        found = await peer.wait(lambda f: f.get('t') in ('paired', 'bye'), self.timeout, start)
        require(found is not None, 'no answer to a pair with a bad approve_sig')
        if found[1].get('t') == 'paired':
            welcome = await peer.wait(lambda f: f.get('t') in ('welcome', 'bye'), self.timeout, found[0] + 1)
            if welcome and welcome[1].get('t') == 'welcome':
                peer.welcome = welcome[1]
                self.adopted = (peer, (device_key, approve_key), found[1], welcome[1])
            raise CheckFailed('a pair whose approve_sig is not by its approve key was accepted (signatures unchecked)')
        require(found[1].get('code') == 'bad_signature', 'a pair with a bad approve_sig got ' + describe(found[1]))
        require(await peer.wait_closed(3), 'the connection stayed open after bye')
        return 'approve_sig by the wrong key refused; the code stays usable'

    async def c_pair(self):
        if self.adopted is not None:  # the bad-signature row failed by pairing: carry on with what it paired
            peer, (device_key, approve_key), paired, welcome = self.adopted
            self.phone.device_key, self.phone.approve_key = device_key, approve_key
            self.phone.device_id, self.epoch, self.main_peer = paired['device_id'], welcome.get('epoch'), peer
            return 'paired by the refused-signature attempt (see the row above)'
        peer = await self.peer('C')
        # X-1: the bridge answers `pair` only after the person confirms the six-digit code on the Mac
        paired, welcome = await peer.pair(self.link['code'], self.phone.device_key, self.phone.approve_key,
                                          wait=self.pair_wait, announce=True)
        self.pair_seconds = peer.pair_seconds
        if paired is not None and paired.get('t') == 'bye' and paired.get('code') == 'bad_code':
            raise CheckFailed('pair got bye bad_code after %.1f s: the code was spent by the refused pair above '
                              '(contract 3.2 counts a refused pair as one of five tries and keeps the code), or the '
                              'pairing was not confirmed on the Mac (X-1: confirm the code above; show a new link to '
                              'rerun)' % (self.pair_seconds or 0))
        require(paired is not None, 'no answer to pair within %g s (X-1: the person confirms the code on the Mac; '
                                    'the bridge gives up after two minutes)' % self.pair_wait)
        require(paired.get('t') == 'paired', 'pair got ' + describe(paired) + ' (' + str(paired.get('error')) + ')')
        require(isinstance(paired.get('device_id'), str) and paired['device_id'], 'paired has no device_id')
        require(welcome is not None and welcome.get('t') == 'welcome', 'no welcome after paired')
        self.phone.device_id = paired['device_id']
        self.epoch = welcome.get('epoch')
        self.main_peer = peer
        return 'device ' + paired['device_id'][:8] + '... after %.1f s' % (self.pair_seconds or 0)

    async def c_sas_formula(self):
        """X-1: the code both sides show. The checker's own formula must give the fixed vectors (the phone's tests use
        the same ones), and this pairing's code is the one the Mac was to show: the checker printed it before `pair`."""
        for index, vector in enumerate(wire.SAS_VECTORS):
            got = wire.sas_code(wire.t_pair(*vector['fields']))
            require(got == vector['code'], 'the formula gives %s for vector %d, not %s' % (got, index, vector['code']))
        require(self.pair_sas is not None and len(self.pair_sas) == 6 and self.pair_sas.isdigit(),
                'no six-digit code for this pairing')
        return 'vectors %s ok; this pairing\'s code was %s' % (', '.join(v['code'] for v in wire.SAS_VECTORS),
                                                              self.pair_sas)

    async def c_pair_confirmed(self):
        """X-1: `paired` never comes before the person has confirmed. Only the time can be seen from here: a person
        reading two codes answers in seconds, a bridge that confirms for itself answers at once."""
        seconds = self.pair_seconds
        require(seconds is not None, 'the pairing time was not measured')
        require(seconds >= self.MIN_CONFIRM_SECONDS,
                'paired came %.2f s after pair: X-1 holds it until the person confirms the code on the Mac (a bridge '
                'that confirms by itself should wait about 1.5 s, so the phone can show its code)' % seconds)
        return 'paired came %.1f s after pair, after the confirmation of code %s' % (seconds, self.pair_sas)

    async def _run_refused(self):
        """--expect-pair-refused: the person cancels the pairing on the Mac (or leaves it unanswered), and the run is
        about that: `bye` `bad_code`, then a spent code. Run it as well as the normal run (which confirms)."""
        await self.check('transport: TLS 1.3, the pinned key, the subprotocol', self.c_transport)
        if await self.check(self.X1_REFUSED, self.c_pair_refused):
            await self.check(self.X1_SPENT, self.c_refused_code_spent)
        else:
            self.skip([self.X1_SPENT], 'the pairing was not refused')

    async def c_pair_refused(self):
        peer = await self.peer('R')
        paired, _ = await peer.pair(self.link['code'], wire.SigningKey(), wire.SigningKey(), wait=self.pair_wait,
                                    announce=True)
        require(paired is not None, 'no answer within %g s: X-1 gives up after two minutes without an answer (bye '
                                    'bad_code)' % self.pair_wait)
        require(paired.get('t') == 'bye' and paired.get('code') == 'bad_code',
                'a pairing that was cancelled or not confirmed got ' + describe(paired) + ', expected bye bad_code '
                '(--expect-pair-refused: cancel on the Mac, or leave it)')
        require(isinstance(paired.get('error'), str) and paired['error'], 'bye has no words for the person')
        require(await peer.wait_closed(3), 'the connection stayed open after bye')
        seconds = peer.pair_seconds or 0
        require(seconds <= 125, 'bye came after %.0f s: X-1 gives up after two minutes' % seconds)
        return 'bye bad_code after %.1f s' % seconds

    async def c_refused_code_spent(self):
        peer = await self.peer('R2')
        paired, _ = await peer.pair(self.link['code'], wire.SigningKey(), wire.SigningKey())
        require(paired is not None and paired.get('t') == 'bye' and paired.get('code') == 'bad_code',
                'the code of a refused pairing was used again: ' + describe(paired))
        require(await peer.wait_closed(3), 'the connection stayed open after bye')
        return 'a second pairing with the same code got bye bad_code at once'

    async def c_welcome(self, peer):
        welcome = peer.welcome
        require(welcome.get('v') == 1, 'v is not 1')
        require(isinstance(welcome.get('epoch'), str) and welcome['epoch'], 'epoch is not a string')
        require(type(welcome.get('seq')) is int and welcome['seq'] >= 0, 'seq is not a whole number')
        require(welcome.get('resumed') is False, 'resumed must be false right after pairing')
        bridge, pebble = welcome.get('bridge'), welcome.get('pebble')
        require(isinstance(bridge, dict) and isinstance(bridge.get('version'), str) and
                isinstance(bridge.get('name'), str), 'bridge {version, name} missing')
        require(isinstance(pebble, dict) and isinstance(pebble.get('running'), bool), 'pebble {running} missing')
        require(not pebble['running'] or isinstance(pebble.get('version'), str), 'pebble.version missing')
        methods, elevated = welcome.get('methods'), welcome.get('elevated')
        require(isinstance(methods, list) and all(isinstance(m, str) for m in methods), 'methods is not a list')
        require(isinstance(elevated, list) and all(isinstance(m, str) for m in elevated), 'elevated is not a list')
        missing = sorted(CORE - set(methods))
        require(not missing, 'methods lacks ' + ', '.join(missing))
        self.v05 = 'remote.folders' in methods  # proposal v0.5: the opening methods are allowed (elevated) too
        self.v06 = 'remote.folder_create' in methods  # proposal v0.6: a new folder, made from the phone
        require(not self.v06 or self.v05, 'remote.folder_create is offered without remote.folders: a new folder is made '
                'in a folder the listing shows (proposal v0.6)')
        excluded = sorted(m for m in methods if wire.phone_excluded(m, self.v05) or
                          (m.startswith('remote.') and m not in wire.REMOTE_METHODS))
        require(not excluded, 'methods offers what section 3.7 excludes: ' + ', '.join(excluded[:8]))
        require({'approve', 'approve_simple'} & set(methods), 'neither approve nor approve_simple is offered')
        require('remote.unlock' in methods and 'remote.unlock' in elevated, 'remote.unlock is not offered as elevated')
        unlisted = sorted(m for m in methods if m in wire.ELEVATED_ALWAYS and m not in elevated)
        require(not unlisted, 'offered but not elevated (section 3.6): ' + ', '.join(unlisted))
        strays = [e for e in elevated if not (e in methods or (e.startswith('setting:') and len(e) > 8))]
        require(not strays, 'elevated names what is not offered: ' + ', '.join(strays[:6]))
        require('setting:permissions' in elevated, 'setting:permissions is not elevated (v0.3 item 5)')
        require(type(welcome.get('unlock_seconds')) is int and welcome['unlock_seconds'] > 0,
                'unlock_seconds missing (C1, the 00:40 answer)')
        limits = welcome.get('limits')
        require(isinstance(limits, dict) and type(limits.get('max_request')) is int and limits['max_request'] > 0 and
                type(limits.get('max_frame')) is int and limits['max_frame'] >= limits['max_request'],
                'limits {max_request, max_frame} missing')
        self.methods, self.elevated, self.limits = set(methods), set(elevated), limits
        self.unlock_seconds = welcome['unlock_seconds']
        return '%d methods, %d elevated, unlock %d s' % (len(methods), len(elevated), self.unlock_seconds)

    async def c_code_reuse(self):
        peer = await self.peer('C2')
        paired, _ = await peer.pair(self.link['code'], wire.SigningKey(), wire.SigningKey())
        require(paired is not None and paired.get('t') == 'bye' and paired.get('code') == 'bad_code',
                'the spent code got ' + describe(paired))
        require(await peer.wait_closed(3), 'the connection stayed open after bye')
        return ''

    async def c_bad_hello(self, main):
        wrong_key = await self.peer('D')
        answer = await wrong_key.hello(key=self.phone.approve_key)
        require(answer is not None and answer.get('t') == 'bye' and answer.get('code') == 'bad_signature',
                'signed with the wrong key: got ' + describe(answer))
        require(await wrong_key.wait_closed(3), 'the connection stayed open after bye')
        replay = await self.peer('D2')
        answer = await replay.hello(nonce=main.nonce)  # a hello signed for another connection's challenge
        require(answer is not None and answer.get('t') == 'bye' and answer.get('code') == 'bad_signature',
                "signed over another connection's nonce: got " + describe(answer))
        await replay.wait_closed(3)
        res = await main.request('remote.ping', {'ts': wire.now_ms()})
        require(res.get('ok') is True, 'a refused hello disturbed the paired connection: ' + describe(res))
        return 'wrong key and replayed nonce refused'

    # -- checks: the unlock, proofs, the allowlist --------------------------------------------------------------------

    async def c_reads(self, peer):
        res = await peer.request('state')
        require(res.get('ok') is True, 'state: ' + describe(res) + ' ' + str(res.get('error')))
        state = res.get('result')
        require(isinstance(state, dict) and isinstance(state.get('chats'), list) and
                isinstance(state.get('settings'), dict), "state's result lacks chats and settings")
        self.state = state
        self.permissions = state['settings'].get('permissions')
        stamp = wire.now_ms()
        res = await peer.request('remote.ping', {'ts': stamp})
        require(res.get('ok') is True and isinstance(res.get('result'), dict) and res['result'].get('ts') == stamp and
                is_ms(res['result'].get('mac_ts'), stamp), 'remote.ping: ' + describe(res))
        res = await peer.request('remote.devices')
        require(res.get('ok') is True and isinstance(res.get('result'), list), 'remote.devices: ' + describe(res))
        mine = [d for d in res['result'] if isinstance(d, dict) and d.get('device_id') == self.phone.device_id]
        require(mine and mine[0].get('current') is True, 'remote.devices does not list this phone as current')
        self.device_row = mine[0]
        res = await peer.request('chat_search', {'query': 'conformance'})
        require(res.get('ok') is True, 'chat_search: ' + describe(res))
        res = await peer.request('remote.status')
        require(res.get('ok') is True and isinstance(res.get('result'), dict), 'remote.status: ' + describe(res))
        self.status = res['result']
        return 'state, remote.ping, remote.devices, chat_search, remote.status; %d conversations' % len(state['chats'])

    async def c_private_endpoints(self, peer):
        listed = [host for host, _ in self.link['endpoints']]
        for text in (self.status.get('bridge') or {}).get('endpoints') or []:
            try:
                listed.append(wire.parse_endpoint(text)[0])
            except (ValueError, TypeError, AttributeError):
                raise CheckFailed('remote.status lists an endpoint that is not host:port') from None
        public = sorted({host for host in listed if not wire.private_endpoint(host)})
        require(not public, 'endpoints a phone could reach from the internet: ' + ', '.join(public[:4]))
        return '%d endpoints' % len(listed)

    async def c_locked(self, peer):
        wrong = []
        calls = [('new_chat', {}), ('model_profiles', {}), ('remote.keep_awake', {'on': True})]
        if 'remote.screenshot' in self.methods:
            calls.append(('remote.screenshot', {'display': None}))
        for method, params in calls:
            res = await peer.act(method, params)
            if res.get('ok') is not False or res.get('code') != 'unlock_required':
                wrong.append(method + ' -> ' + describe(res))
        require(not wrong, '; '.join(wrong))
        return ', '.join(method for method, _ in calls)

    def approve_method(self):
        return 'approve' if 'approve' in self.methods else 'approve_simple'

    async def c_proof_required(self, peer):
        method = self.approve_method()
        wrong = []
        plain = [(method, {'id': uuid.uuid4().hex, 'action_id': uuid.uuid4().hex}),
                 ('setting', {'key': 'permissions', 'value': self.permissions}), ('remote.unlock', {})]
        for name, params in plain:
            res = await peer.act(name, params)
            if res.get('ok') is not False or res.get('code') != 'proof_required':
                wrong.append(name + ' -> ' + describe(res))
        require(not wrong, '; '.join(wrong))
        return method + ', setting permissions, remote.unlock'

    async def c_bad_proof(self, peer):
        variants = [
            ('signed with the device key', dict(key=self.phone.device_key)),
            ('ts two minutes old', dict(ts=wire.now_ms() - 120000)),
            ('ts two minutes ahead', dict(ts=wire.now_ms() + 120000)),
            ('params_json changed after signing', dict(params_json='{ }', signed_json='{}')),
            ('signed for another method', dict(sign_method='approve')),
            ('signed for another epoch', dict(epoch='e-not-this-one')),
            ("signed for another connection's nonce", dict(nonce=wire.b64u(os.urandom(32)))),
            ('signed for another idem', dict(sign_idem=new_idem())),
            ("v0.2's transcript (no nonce, no idem)", dict(v02=True)),
        ]
        wrong = []
        for label, options in variants:
            res = await peer.exchange(peer.elevated_frame('remote.unlock', {}, **options))
            if res.get('ok') is not False or res.get('code') != 'bad_proof':
                wrong.append(label + ' -> ' + describe(res))
        require(not wrong, '; '.join(wrong))
        res = await peer.act('new_chat', {})
        require(res.get('code') == 'unlock_required', 'a refused proof unlocked the device: ' + describe(res))
        return '%d variants of remote.unlock refused; still locked' % len(variants)

    async def c_unlock(self, peer):
        frame = peer.elevated_frame('remote.unlock', {})
        before = wire.now_ms()
        res = await peer.exchange(frame)
        require(res.get('ok') is True and isinstance(res.get('result'), dict), 'remote.unlock: ' + describe(res))
        until = res['result'].get('unlocked_until')
        require(is_ms(until, before + self.unlock_seconds * 1000, 60000),
                'unlocked_until is not unix ms about unlock_seconds from now')
        self.unlock_frame, self.unlocked_until = frame, until
        key = new_idem()
        first = await peer.request('new_chat', {}, idem=key)
        require(first.get('ok') is True and isinstance(first.get('result'), dict) and first['result'].get('id'),
                'new_chat after the unlock: ' + describe(first) + ' ' + str(first.get('error')))
        self.chat_id, self.new_chat_idem, self.new_chat_answer = first['result']['id'], key, first['result']
        return 'unlocked for %d s; new_chat works' % self.unlock_seconds

    async def c_good_proof(self, peer):
        frame = peer.elevated_frame('setting', {'key': 'permissions', 'value': self.permissions})
        res = await peer.exchange(frame)
        require(res.get('code') not in ('proof_required', 'bad_proof', 'not_allowed', 'unlock_required'),
                'setting permissions with a valid proof: ' + describe(res))
        note = 'setting permissions ok' if res.get('ok') else 'setting permissions reached Pebble, which refused'
        again = peer.elevated_frame('setting', {'key': 'permissions', 'value': self.permissions},
                                    request_id=frame['id'])
        res2 = await peer.exchange(again)
        require(res2.get('ok') is False and res2.get('code') == 'bad_proof',
                'a valid proof reusing a request id of this connection: ' + describe(res2))
        method = self.approve_method()
        approve = peer.elevated_frame(method, {'id': self.chat_id, 'action_id': uuid.uuid4().hex})
        res3 = await peer.exchange(approve)
        require(res3.get('code') not in BRIDGE_CODES, method + ' with a valid proof: ' + describe(res3))
        require(res3.get('ok') is False, method + ' of a card that does not exist succeeded')
        return note + '; id reuse refused; ' + method + ' reached Pebble'

    async def c_not_allowed(self, peer):
        # v0.5 allows the opening methods (elevated; their own row checks them), so a v0.5 bridge is not asked to refuse
        never = [m for m in NEVER if not (self.v05 and m in wire.OPEN_ON_MAC)]
        wrong = []
        for method in never:
            res = await peer.act(method, {'conformance_check': True})
            if res.get('ok') is not False or res.get('code') != 'not_allowed':
                wrong.append(method + ' -> ' + describe(res))
        require(not wrong, '; '.join(wrong[:4]))
        return '%d refused (local files, sign-ins, installs, %snative-only, unknown)' % (
            len(never), '' if self.v05 else 'the Mac screen, ')

    async def c_setting_keys(self, peer):
        settings = dict(self.state.get('settings') or {})
        if 'notification_status' in self.methods:
            status = await peer.request('notification_status')
            if status.get('ok') and isinstance(status.get('result'), dict):
                settings['notifications'] = status['result'].get('settings')
        keys = sorted(e.split(':', 1)[1] for e in self.elevated if e.startswith('setting:'))
        wrong = []
        for key in keys:
            res = await peer.act('setting', {'key': key, 'value': settings.get(key)})  # its current value: harmless
            if res.get('ok') is not False or res.get('code') != 'proof_required':
                wrong.append(key + ' -> ' + describe(res))
        require(not wrong, 'without a proof: ' + '; '.join(wrong))
        plain = next((k for k in ('theme', 'reduced_motion', 'stealth', 'fast_replies')
                      if k in settings and k not in keys), None)
        if plain is None:
            return '%d keys need a proof (no plain key to try)' % len(keys)
        self.plain_key = (plain, settings[plain])
        res = await peer.act('setting', {'key': plain, 'value': settings[plain]})
        require(res.get('ok') is True, 'setting %s (not elevated) without a proof: %s' % (plain, describe(res)))
        return '%s need a proof; %s does not' % (', '.join(keys), plain)

    async def c_setting_smuggling(self, peer):
        """The bridge must decide a setting's proof from exactly what it relays to Pebble: a key given twice (Pebble's
        JSON keeps the last), a key that is not a string, or another spelling of an elevated key must never change a
        setting without a proof. Each variant sends the value the setting already has, so even a bridge that relays
        it changes nothing; it only has to answer ok:false."""
        if 'setting:permissions' not in self.elevated:
            raise Skipped('setting:permissions is not elevated')
        value = json.dumps(self.permissions, separators=(',', ':'))
        plain = (self.plain_key or ('theme', 'system'))[0]
        variants = [
            ('the key twice, permissions last', '{"key":%s,"key":"permissions","value":%s}' % (json.dumps(plain),
                                                                                           value)),
            ('a key that is not a string', '{"key":["permissions"],"value":%s}' % value),
            ('a key of another case', '{"key":"Permissions","value":%s}' % value),
            ('a key with a trailing space', '{"key":"permissions ","value":%s}' % value),
        ]
        wrong = []
        for label, params in variants:
            request_id = peer.next_id()
            text = '{"t":"req","id":"%s","method":"setting","params":%s,"idem":"%s"}' % (request_id, params, new_idem())
            await self.pacer.take()
            start = len(peer.frames)
            await peer.ws.send_text(text)
            found = await peer.wait(lambda f: f.get('t') == 'res' and f.get('id') == request_id, self.timeout, start)
            require(found is not None, 'no answer to setting with ' + label)
            if found[1].get('ok') is not False:
                wrong.append(label + ' -> ' + describe(found[1]))
        require(not wrong, 'changed a setting without a proof: ' + '; '.join(wrong))
        return '%d variants refused' % len(variants)

    async def c_request_ids(self, peer):
        wrong = []
        for label, ident in (('a space', 'has space'), ('a dot', 'dot.ted'), ('65 characters', 'x' * 65),
                             ('a line break', 'line\nbreak'), ('empty', '')):
            frame = {'t': 'req', 'id': ident, 'method': 'remote.ping', 'params': {'ts': 1}}
            res = await peer.exchange(frame, any_id=True)
            if res.get('ok') is not False or res.get('code') != 'bad_request':
                wrong.append(label + ' -> ' + describe(res))
        require(not wrong, '; '.join(wrong))
        good = await peer.request('remote.ping', {'ts': 2}, request_id='Az09_-' + 'y' * 58)
        require(good.get('ok') is True, 'a 64-character id in the charset was refused: ' + describe(good))
        return 'space, dot, 65 characters, line break, empty refused; 64 accepted'

    async def c_idem(self, peer):
        again = await peer.request('new_chat', {}, idem=self.new_chat_idem)
        require(again.get('ok') is True and again.get('result') == self.new_chat_answer,
                'the new_chat repeat did not return the first answer (a second conversation was made?)')
        wrong = []
        calls = [('chat_rename', {'id': self.chat_id, 'title': 'New conversation'})]
        if self.plain_key:
            calls.append(('setting', {'key': self.plain_key[0], 'value': self.plain_key[1]}))
        for method, params in calls:
            res = await peer.request(method, params)
            if res.get('ok') is not False or res.get('code') != 'bad_request':
                wrong.append(method + ' -> ' + describe(res))
        require(not wrong, 'without idem: ' + '; '.join(wrong))
        return 'new_chat answered twice with one conversation; ' + ', '.join(m for m, _ in calls) + ' need idem'

    # -- checks: proposal v0.5 (folders, connecting a project, opening things on the Mac) ------------------------------

    async def run_v05(self, main):
        """The v0.5 rows, after the unlock. A bridge that does not offer remote.folders follows v0.3 only."""
        if not self.v05:
            self.record('v0.5: remote.folders, connecting a folder, opening things on the Mac', None,
                        'not offered: this bridge follows contract v0.3 only')
            return
        if await self.check(self.V05_LISTING, self.c_folders, main):
            await self.check(self.V05_OUTSIDE, self.c_folders_outside, main)
            await self.check(self.V05_PRIVATE, self.c_folders_private, main)
            await self.check(self.V05_LINKS, self.c_links, main)
            await self.check(self.V05_WORKSPACE, self.c_set_workspace, main)
            await self.check(self.V05_NEW_CHAT, self.c_new_chat_workspace, main)
        else:
            self.skip(self.V05_ROWS[1:6], 'the folder listing failed')
        await self.check(self.V05_OPEN, self.c_open_elevated, main)

    async def c_folders_locked(self, peer):
        res = await peer.act('remote.folders', {})
        require(res.get('ok') is False and res.get('code') == 'unlock_required',
                'remote.folders before the unlock: got ' + describe(res) + ', expected unlock_required (it shows the '
                "names of the Mac's folders)")
        return "a listing of the Mac's folders needs the unlock"

    @staticmethod
    def read_listing(res, what):
        """A `remote.folders` answer, checked against the proposal's shape: {home, path, parent, folders: [{name, path,
        is_project}]}, sorted by name, at most 500, with no hidden or protected folder. Messages carry no folder names."""
        require(res.get('ok') is True and isinstance(res.get('result'), dict),
                '%s: %s %s' % (what, describe(res), res.get('error') or ''))
        listing = res['result']
        for key in ('home', 'path', 'parent', 'folders'):
            require(key in listing, '%s: the answer has no "%s"' % (what, key))
        home, here, parent, folders = listing['home'], listing['path'], listing['parent'], listing['folders']
        for label, value in (('home', home), ('path', here)):
            require(isinstance(value, str) and value.startswith('/') and (value == '/' or not value.endswith('/')),
                    '%s: %s is not an absolute folder path' % (what, label))
        require(here == home or here.startswith(home + '/'), '%s: path is not inside home' % what)
        if here == home:
            require(parent is None, '%s: parent must be null at the home folder' % what)
        else:
            require(parent == posixpath.dirname(here), '%s: parent is not the folder above path' % what)
        require(isinstance(folders, list), '%s: folders is not a list' % what)
        require(len(folders) <= wire.FOLDERS_LIMIT,
                '%s: %d folders, at most %d' % (what, len(folders), wire.FOLDERS_LIMIT))
        names = []
        for row in folders:
            require(isinstance(row, dict) and isinstance(row.get('name'), str) and row['name'] and
                    '/' not in row['name'], '%s: a folder has no name' % what)
            require(row.get('path') == posixpath.join(here, row['name']),
                    '%s: a folder path is not path plus name' % what)
            require(type(row.get('is_project')) is bool, '%s: is_project is not true or false' % what)
            names.append(row['name'])
        require(len(set(names)) == len(names), '%s: a folder is listed twice' % what)
        folded = [name.casefold() for name in names]
        require(names == sorted(names) or folded == sorted(folded), '%s: the folders are not sorted by name' % what)
        for row in folders:
            require(not row['name'].startswith('.'), '%s: a hidden folder is listed' % what)
            entry = wire.protected_entry(home, row['path'], realpath=posixpath.normpath, exists=lambda path: True)
            require(entry is None, '%s: a protected folder is listed (%s)' % (what, entry))
        return listing

    async def c_folders(self, peer):
        home_listing = self.read_listing(await peer.act('remote.folders', {}), 'remote.folders')
        require(home_listing['path'] == home_listing['home'], 'with no path, remote.folders must list the home folder')
        explicit = self.read_listing(await peer.act('remote.folders', {'path': None}), 'remote.folders with path null')
        require(explicit == home_listing, 'path null and no path gave different answers')
        home = home_listing['home']
        child = next((row for row in home_listing['folders'] if row['name'] not in AVOID), None)
        self.folder_home, self.folder_listing, self.folder_child = home, home_listing, child
        folders = home_listing['folders']
        detail = '%d folders at home (%d with .git)' % (len(folders), sum(1 for row in folders if row['is_project']))
        if child is None:
            return detail + '; no folder to go into'
        inner = self.read_listing(await peer.act('remote.folders', {'path': child['path']}),
                                  'remote.folders in a folder')
        require(inner['home'] == home and inner['path'] == child['path'], 'in a folder: home or path changed')
        require(inner['parent'] == home, 'in a folder at home: parent is not the home folder')
        up = self.read_listing(await peer.act('remote.folders', {'path': inner['parent']}),
                               'remote.folders at the parent')
        require(up['path'] == home and up['parent'] is None, 'the parent did not lead back to the home folder')
        return detail + '; went into one folder (%d folders) and back up' % len(inner['folders'])

    async def c_folders_outside(self, peer):
        home, child = self.folder_home, self.folder_child
        cases = [('/', '/'), ('/etc', '/etc'), ('/usr', '/usr'), ('home/..', home + '/..'),
                 ('home/../..', home + '/../..')]
        if home != '/':
            cases.append(('the folder above home', posixpath.dirname(home)))
        if child is not None:
            cases.append(('a folder/../..', child['path'] + '/../..'))
        wrong = []
        for label, path in cases:
            res = await peer.act('remote.folders', {'path': path})
            if res.get('ok') is not False or res.get('code') != 'not_allowed':
                wrong.append('%s -> %s' % (label, describe(res)))
        for label, value in (('a number', 5), ('a list', [home])):
            res = await peer.act('remote.folders', {'path': value})
            if res.get('ok') is not False:
                wrong.append('%s -> %s' % (label, describe(res)))
        require(not wrong, 'expected not_allowed (and a refusal for a path that is not a string), got ' +
                '; '.join(wrong))
        return '%d places outside home or with .. got not_allowed; a path that is not a string is refused' % len(cases)

    async def c_folders_private(self, peer):
        names = ('.ssh', '.pebble', '.claude', 'PebbleBackups')
        wrong, codes = [], set()
        for name in names:
            res = await peer.act('remote.folders', {'path': self.folder_home + '/' + name})
            codes.add(str(res.get('code') or 'words'))
            if res.get('ok') is not False:
                wrong.append('%s -> %s' % (name, describe(res)))
        require(not wrong, 'a hidden or protected folder was not refused (expected ok:false): ' + '; '.join(wrong))
        return ('no hidden or protected folder in the listing; %s refused when asked for (%s)'
                % (', '.join(names), ', '.join(sorted(codes))))

    def own_home(self):
        """The bridge's home folder, when the checker may write in it: this user's home folder or a tree in a temporary
        folder, writable. Anything else is a skipped row."""
        home = self.folder_home
        temporary = [os.path.realpath(path) for path in (tempfile.gettempdir(), '/tmp')]
        if not (os.path.isdir(home) and os.access(home, os.W_OK) and
                (home == os.path.realpath(os.path.expanduser('~')) or
                 any(home.startswith(path.rstrip('/') + '/') for path in temporary))):
            raise Skipped("the bridge's home folder is not this user's home folder or a tree in a temporary folder, so "
                          'the checker does not write in it')
        return home

    async def c_links(self, peer):
        """claude-w's 10:53 addition: a `path` that is itself a link, or that resolves outside home, gets `not_allowed`:
        in `remote.folders`, and in `set_workspace` and `new_chat` with a proof. A link can be made only on the Mac the
        bridge runs on, so the checker makes two in the home folder when it runs on loopback (named
        pebble-remote-conformance-<random>, one to a folder inside home and one to /usr), and takes them away again
        when the row is done. Any other endpoint, or --no-link-probe, skips the row."""
        if not self.link_probe:
            raise Skipped('--no-link-probe')
        if not self.loopback:
            raise Skipped('a link can be made only on the Mac the bridge runs on: run the checker on it '
                          '(--endpoint 127.0.0.1:<port>)')
        home = self.own_home()
        stamp = uuid.uuid4().hex[:10]
        links = {'a link to a folder inside home': os.path.join(home, 'pebble-remote-conformance-%s-in' % stamp),
                 'a link to /usr': os.path.join(home, 'pebble-remote-conformance-%s-out' % stamp)}
        targets = {'a link to a folder inside home': self.folder_child['path'] if self.folder_child else home,
                   'a link to /usr': '/usr'}
        made = []
        try:
            try:
                for label, path in links.items():
                    os.symlink(targets[label], path)
                    made.append(path)
            except OSError as exc:
                raise Skipped('could not make a link in the home folder (%s)' % type(exc).__name__) from None
            inside, outside = links['a link to a folder inside home'], links['a link to /usr']
            asked = [('a link to a folder inside home', inside), ('a link to /usr', outside),
                     ('a path below a link out of home', outside + '/bin'),
                     ('a link named with a trailing slash', inside + '/')]
            wrong = []
            for label, path in asked:
                res = await peer.act('remote.folders', {'path': path})
                if res.get('ok') is not False or res.get('code') != 'not_allowed':
                    wrong.append('%s -> %s' % (label, describe(res)))
            require(not wrong, 'remote.folders: expected not_allowed for ' + '; '.join(wrong))
            listing = self.read_listing(await peer.act('remote.folders', {}), 'remote.folders')
            shown = [row['name'] for row in listing['folders'] if row['name'].startswith('pebble-remote-conformance-')]
            require(not shown, 'a link is listed as a folder')
            chat = self.chat_id
            for label, path in asked[:2]:
                res = await peer.exchange(peer.elevated_frame('set_workspace', {'id': chat, 'path': path}))
                if res.get('ok') is True:
                    await self.put_back(peer)
                    raise CheckFailed('set_workspace with a proof connected ' + label)
                require(res.get('code') == 'not_allowed',
                        'set_workspace with a proof for %s: got %s, expected not_allowed' % (label, describe(res)))
            res = await peer.exchange(peer.elevated_frame('new_chat', {'workspace': inside}))
            require(res.get('ok') is False and res.get('code') == 'not_allowed',
                    'new_chat with a proof for a link: got ' + describe(res) + ', expected not_allowed')
        finally:
            for path in made:
                with contextlib.suppress(OSError):
                    os.unlink(path)
        return ('remote.folders, set_workspace and new_chat refused a link inside home, a link out of it, a path below '
                'it and a trailing slash; the links are gone again')

    def projects_in_use(self):
        """The workspaces conversations on the Mac use, from the state the first read returned."""
        chats = (self.state or {}).get('chats') or []
        return [c['workspace'] for c in chats if isinstance(c, dict) and isinstance(c.get('workspace'), str) and
                c['workspace']]

    async def put_back(self, peer):
        """The checker's own conversation back to the Companion (path null needs only the unlock)."""
        res = await peer.act('set_workspace', {'id': self.chat_id, 'path': None})
        require(res.get('ok') is True, "taking the folder off the checker's own conversation again: " +
                describe(res) + ' ' + str(res.get('error') or ''))

    async def c_set_workspace(self, peer):
        chat, child, notes = self.chat_id, self.folder_child, []
        res = await peer.act('set_workspace', {'id': chat, 'path': None})
        require(res.get('ok') is True, 'path null (back to the Companion) needs only the unlock: ' + describe(res) +
                ' ' + str(res.get('error') or ''))
        notes.append('null needs no proof')
        known = self.projects_in_use()
        if known:
            res = await peer.act('set_workspace', {'id': chat, 'path': known[0]})
            require(res.get('code') not in BRIDGE_CODES,
                    'a project a conversation uses needs only the unlock: ' + describe(res))
            if res.get('ok') is True:
                await self.put_back(peer)
                notes.append('a project in use needs no proof')
            else:
                notes.append('a project in use: Pebble refused it in words (is its folder gone?)')
        else:
            notes.append('no project in use to try')
        if child is None:
            raise Skipped('; '.join(notes) + '; no listed folder to try as a new one')
        res = await peer.act('set_workspace', {'id': chat, 'path': child['path']})
        if res.get('ok') is True:
            await self.put_back(peer)
            raise CheckFailed('a new folder was connected with no proof: it needs Face ID (proposal v0.5, item 2)')
        require(res.get('code') == 'proof_required', 'a new folder without a proof: got ' + describe(res) + ' ' +
                str(res.get('error') or '') + ', expected proof_required')
        notes.append('a new folder gets proof_required')
        for label, path, strict in (('a place outside home', '/usr', True),
                                    ('a hidden folder', self.folder_home + '/.ssh', False)):
            res = await peer.exchange(peer.elevated_frame('set_workspace', {'id': chat, 'path': path}))
            if res.get('ok') is True:
                await self.put_back(peer)
                raise CheckFailed(label + ' was connected: it must be a folder remote.folders would list')
            require(res.get('code') not in ('proof_required', 'bad_proof', 'unlock_required'),
                    label + ' with a valid proof: ' + describe(res))
            if strict:  # claude-w's 10:53 addition: a path that resolves outside home gets not_allowed
                require(res.get('code') == 'not_allowed',
                        label + ' with a valid proof: got ' + describe(res) + ', expected not_allowed')
        notes.append('folders the listing leaves out are refused even with a proof')
        if not self.connect:
            notes.append('a new folder with a proof not tried (--no-connect)')
            return '; '.join(notes)
        res = await peer.exchange(peer.elevated_frame('set_workspace', {'id': chat, 'path': child['path']}))
        require(res.get('ok') is True,
                'a new folder with a valid proof: ' + describe(res) + ' ' + str(res.get('error') or ''))
        read = await peer.request('get_chat', {'id': chat})
        took = read.get('ok') is True and isinstance(read.get('result'), dict) and \
            read['result'].get('workspace') == child['path']
        await self.put_back(peer)
        require(took, "after a good proof the conversation's workspace is not the folder")
        notes.append('a new folder with a proof is connected, then taken off')
        return '; '.join(notes)

    async def c_new_chat_workspace(self, peer):
        child, notes = self.folder_child, []
        known = self.projects_in_use()
        if known:
            res = await peer.act('new_chat', {'workspace': known[0]})
            require(res.get('code') not in BRIDGE_CODES,
                    'new_chat in a project a conversation uses needs only the unlock: ' + describe(res))
            if res.get('ok') is True:
                workspace = res['result'].get('workspace') if isinstance(res.get('result'), dict) else None
                require(workspace == known[0], 'new_chat did not keep the project as the new conversation\'s workspace')
                notes.append('a project in use is kept as the workspace')
            else:
                notes.append('Pebble refused the project in words (is its folder gone?)')
        else:
            notes.append('no project in use to try')
        if child is None:
            raise Skipped('; '.join(notes) + '; no listed folder to try as a new one')
        res = await peer.act('new_chat', {'workspace': child['path']})
        require(res.get('ok') is not True,
                "new_chat in a new folder was accepted without a proof: it is a way around set_workspace's rule "
                '(proposal v0.5, item 2), so any phone with the unlock could connect any folder of home')
        require(res.get('code') == 'proof_required', 'new_chat in a new folder without a proof: got ' +
                describe(res) + ' ' + str(res.get('error') or '') + ', expected proof_required')
        notes.append('a new folder gets proof_required')
        return '; '.join(notes)

    async def c_open_elevated(self, peer):
        missing = [m for m in wire.OPEN_ON_MAC if m not in self.methods]
        require(not missing, 'welcome.methods lacks ' + ', '.join(missing) + ' (proposal v0.5, item 3)')
        plain = [m for m in wire.OPEN_ON_MAC if m not in self.elevated]
        require(not plain, 'welcome.elevated lacks ' + ', '.join(plain))
        wrong = []
        # Sent without a proof, with a parameter no Pebble route takes: a correct bridge answers proof_required, and
        # even one that relayed it would open nothing (browser_start takes any parameters, so it goes last)
        for method in sorted(wire.OPEN_ON_MAC, key=lambda name: name == 'browser_start'):
            res = await peer.act(method, {'conformance_check': True})
            if res.get('ok') is not False or res.get('code') != 'proof_required':
                wrong.append(method + ' -> ' + describe(res))
        require(not wrong, 'without a proof, expected proof_required: ' + '; '.join(wrong))
        return '%d methods are elevated, and each one without a proof got proof_required' % len(wire.OPEN_ON_MAC)

    # -- checks: proposal v0.6 (a new folder, made from the phone) -----------------------------------------------------

    async def run_v06(self, main):
        """The v0.6 rows, after the v0.5 ones. A bridge that offers remote.folders but not remote.folder_create follows
        v0.5 only."""
        if not self.v06:
            if self.v05:
                self.record('v0.6: remote.folder_create, and connecting a folder this device made', None,
                            'not offered: this bridge follows v0.5 only')
            return
        if self.folder_home is None:
            self.skip(self.V06_ROWS, 'the folder listing failed')
            return
        await self.check(self.V06_CREATE, self.c_create, main)
        await self.check(self.V06_REFUSALS, self.c_create_refusals, main)
        await self.check(self.V06_CONNECT, self.c_create_connect, main)

    def create_ground(self):
        """The home folder, where the v0.6 rows make their folders and remove them again; or a skipped row. A folder can
        be removed only on the Mac the bridge runs on, so only on loopback."""
        if not self.create_probe:
            raise Skipped('--no-create-probe')
        if not self.loopback:
            raise Skipped('a folder it makes can be removed only on the Mac the bridge runs on: run the checker on it '
                          '(--endpoint 127.0.0.1:<port>)')
        return self.own_home()

    @staticmethod
    def remove_folders(paths):
        """Takes away the folders a row made (innermost first); a path that is not there is fine."""
        for path in paths:
            with contextlib.suppress(OSError):
                os.rmdir(path)

    @staticmethod
    async def make_folder(peer, parent, name):
        """`remote.folder_create` with a proof: the whole answer."""
        return await peer.exchange(peer.elevated_frame('remote.folder_create', {'parent': parent, 'name': name}))

    async def c_create(self, peer):
        """Proposal v0.6, item 1: `remote.folder_create {parent, name}` is elevated, makes one empty folder in `parent` and
        answers its entry as `remote.folders` gives it, `{path, name, is_project: false}`. The checker asks for one in the
        home folder (named pebble-remote-conformance-<random>-made) and removes it at the end."""
        home = self.create_ground()
        name = 'pebble-remote-conformance-%s-made' % uuid.uuid4().hex[:10]
        path = posixpath.join(home, name)
        try:
            plain = await peer.act('remote.folder_create', {'parent': home, 'name': name})
            require(plain.get('ok') is False and plain.get('code') == 'proof_required',
                    'without a proof: got ' + describe(plain) + ', expected proof_required (it writes to the Mac)')
            require(not os.path.lexists(path), 'a folder was made without a proof')
            res = await self.make_folder(peer, home, name)
            require(res.get('ok') is True and isinstance(res.get('result'), dict),
                    'with a proof: ' + describe(res) + ' ' + str(res.get('error') or ''))
            made = res['result']
            require(set(made) == {'path', 'name', 'is_project'}, 'the answer is not {path, name, is_project}')
            require(made['path'] == path and made['name'] == name and made['is_project'] is False,
                    'the answer is not the new folder as remote.folders gives an entry (path = parent + name, '
                    'is_project false)')
            require(os.path.isdir(path) and not os.path.islink(path), 'with a proof, no folder was made')
            require(os.listdir(path) == [], 'the new folder is not empty')
            listing = self.read_listing(await peer.act('remote.folders', {}), 'remote.folders')
            if len(listing['folders']) < wire.FOLDERS_LIMIT:  # a cut listing may leave it out
                require({'name': name, 'path': path, 'is_project': False} in listing['folders'],
                        'the new folder is not in the listing of its parent')
        finally:
            self.remove_folders([path])
        return 'a proof was needed; one empty folder was made, the listing shows it, and it is removed again'

    async def c_create_refusals(self, peer):
        """Proposal v0.6, item 1: a parent outside the rules gets `not_allowed`; a name outside the rules gets
        `bad_request` (and no folder is made, intermediate ones either); a name already there gets words and no code.
        Every call is sent with a proof, so only the rules can refuse it."""
        home = self.create_ground()
        base = 'pebble-remote-conformance-%s' % uuid.uuid4().hex[:10]
        wrong, leftovers, notes = [], [], []   # leftovers: (what was asked, the path a faulty bridge would have made)
        counts = {'names': 0, 'parents': 0}

        async def refused(label, params, codes, kind, made=()):
            res = await peer.exchange(peer.elevated_frame('remote.folder_create', params))
            leftovers.extend((label, path) for path in made)
            counts[kind] += 1
            if res.get('ok') is not False:
                wrong.append('%s -> %s' % (label, describe(res)))
            elif res.get('code') not in codes:
                wrong.append('%s -> %s, expected %s' % (label, describe(res), ' or '.join(str(c) for c in codes)))
            elif not res.get('error'):
                wrong.append('%s -> a refusal without words' % label)

        try:
            names = [('an empty name', '', []), ('a name of blanks', '   ', []), ('the name "."', '.', []),
                     ('the name ".."', '..', []), ('a leading dot', '.' + base, [posixpath.join(home, '.' + base)]),
                     ('a slash', base + '-a/b', [posixpath.join(home, base + '-a', 'b'), posixpath.join(home, base + '-a')]),
                     ('a colon', base + ':b', [posixpath.join(home, base + ':b')]),
                     ('a line break', base + '\nb', [posixpath.join(home, base + '\nb')]),
                     ('a control character', base + '\x07b', [posixpath.join(home, base + '\x07b')]),
                     ('256 bytes', 'x' * 256, []), ('256 bytes in two-byte letters', 'é' * 128, [])]
            for label, name, made in names:
                await refused(label, {'parent': home, 'name': name}, ('bad_request',), 'names', made)
            for label, params in (('a name that is a number', {'parent': home, 'name': 5}),
                                  ('a name that is a list', {'parent': home, 'name': [base]}),
                                  ('no name', {'parent': home}), ('no parent', {'name': base + '-np'}),
                                  ('a parent that is null', {'parent': None, 'name': base + '-nl'}),
                                  ('a parent that is a number', {'parent': 5, 'name': base + '-pn'})):
                await refused(label, params, ('bad_request', 'not_allowed'), 'names',
                              [posixpath.join(home, params['name'])] if isinstance(params.get('name'), str) else [])
            name = base + '-in'
            parents = [('the root', '/', 'not_allowed'), ('/usr', '/usr', 'not_allowed'),
                       ('home/..', home + '/..', 'not_allowed')]
            if home != '/':
                parents.append(('the folder above home', posixpath.dirname(home), 'not_allowed'))
            for label, parent, code in parents:
                await refused(label, {'parent': parent, 'name': name}, (code,), 'parents',
                              [posixpath.join(parent, name)])
            for hidden in ('.ssh', '.pebble', '.claude', 'PebbleBackups'):  # hidden or protected: refused, there or not
                await refused('a hidden or protected folder', {'parent': home + '/' + hidden, 'name': name},
                              ('not_allowed', None), 'parents', [posixpath.join(home, hidden, name)])
            missing = base + '-missing'
            await refused('a parent that is not there', {'parent': posixpath.join(home, missing), 'name': name},
                          ('not_allowed', None), 'parents',
                          [posixpath.join(home, missing, name), posixpath.join(home, missing)])
            if self.link_probe:
                inside_target = self.folder_child['path'] if self.folder_child else home
                links = {'a link to a folder inside home': (posixpath.join(home, base + '-lin'), inside_target),
                         'a link to /usr': (posixpath.join(home, base + '-lout'), '/usr')}
                made = []
                try:
                    try:
                        for label, (link, target) in links.items():
                            os.symlink(target, link)
                            made.append(link)
                    except OSError as exc:
                        notes.append('links not tried (could not make one: %s)' % type(exc).__name__)
                    else:
                        for label, (link, target) in links.items():
                            await refused('a parent that is ' + label, {'parent': link, 'name': name},
                                          ('not_allowed',), 'parents', [posixpath.join(target, name)])
                finally:
                    for link in made:
                        with contextlib.suppress(OSError):
                            os.unlink(link)
            else:
                notes.append('links not tried (--no-link-probe)')
            first = await self.make_folder(peer, home, base + '-dup')
            leftovers.append(('a name already there (made on purpose)', posixpath.join(home, base + '-dup')))
            require(first.get('ok') is True, 'a folder for the already-there check: ' + describe(first) + ' ' +
                    str(first.get('error') or ''))
            again = await self.make_folder(peer, home, base + '-dup')
            if again.get('ok') is not False or again.get('code') is not None or not again.get('error'):
                wrong.append('a name already there -> %s, expected words with no code' % describe(again))
            for label, path in leftovers:
                if label != 'a name already there (made on purpose)' and os.path.lexists(path):
                    wrong.append('a folder was made for ' + label)
        finally:
            self.remove_folders([path for _, path in reversed(leftovers)])
        require(not wrong, 'refused wrongly: ' + '; '.join(wrong))
        return ('%d names and %d parents outside the rules were refused (bad_request, not_allowed), none made a folder, '
                'and a name already there got words with no code%s'
                % (counts['names'], counts['parents'], ''.join('; ' + note for note in notes)))

    async def c_create_connect(self, peer):
        """Proposal v0.6, item 2: a folder this device made in the last ten minutes counts as known for this device, so
        `set_workspace` and `new_chat {workspace}` with exactly that path need only the unlock (one Face ID for "make it and
        connect it"). Another folder that no conversation uses still needs a proof. The checker puts its conversation
        back in the Companion, and removes the folder."""
        if not self.connect:
            raise Skipped('--no-connect')
        home = self.create_ground()
        chat = self.chat_id
        name = 'pebble-remote-conformance-%s-connect' % uuid.uuid4().hex[:10]
        path = posixpath.join(home, name)
        notes = []
        try:
            res = await self.make_folder(peer, home, name)
            require(res.get('ok') is True and isinstance(res.get('result'), dict),
                    'remote.folder_create with a proof: ' + describe(res) + ' ' + str(res.get('error') or ''))
            made = path  # the answer's own path is the create row's business
            moved = await peer.act('set_workspace', {'id': chat, 'path': made})
            if moved.get('ok') is True:
                read = await peer.request('get_chat', {'id': chat})
                took = read.get('ok') is True and isinstance(read.get('result'), dict) and \
                    read['result'].get('workspace') == made
                await self.put_back(peer)
                require(took, "after set_workspace the conversation's workspace is not the folder this device made")
            else:
                raise CheckFailed('set_workspace with the folder this device just made, and the unlock alone: got ' +
                                  describe(moved) + ' ' + str(moved.get('error') or '') +
                                  ' (proposal v0.6, item 2: it counts as known for ten minutes)')
            notes.append('set_workspace needed no proof')
            opened = await peer.act('new_chat', {'workspace': made})
            require(opened.get('ok') is True and isinstance(opened.get('result'), dict) and
                    opened['result'].get('workspace') == made,
                    'new_chat with the folder this device just made, and the unlock alone: got ' + describe(opened) +
                    ' ' + str(opened.get('error') or ''))
            notes.append('new_chat needed no proof')
            in_use = set(self.projects_in_use())
            other = next((row for row in (self.folder_listing or {}).get('folders', [])
                          if row['name'] not in AVOID and row['path'] not in in_use and row['path'] != made), None)
            if other is None:
                notes.append('no other folder to check that only the made one is known')
            else:
                res = await peer.act('set_workspace', {'id': chat, 'path': other['path']})
                if res.get('ok') is True:
                    await self.put_back(peer)
                    raise CheckFailed('after a folder was made, another listed folder was connected with the unlock '
                                      'alone: only the folder this device made may be known (exactly that path)')
                require(res.get('code') == 'proof_required',
                        'another listed folder after one was made, with no proof: got ' + describe(res) +
                        ', expected proof_required')
                notes.append('another folder still gets proof_required')
        finally:
            self.remove_folders([path])
        return '; '.join(notes)

    # -- checks: S-05, the unlock that ends -----------------------------------------------------------------------------

    async def reunlock(self, peer):
        """What the phone does after `unlock_required`: Face ID (here, an elevated remote.unlock), then on."""
        res = await peer.exchange(peer.elevated_frame('remote.unlock', {}))
        require(res.get('ok') is True, 'remote.unlock (after the unlock ended): ' + describe(res) + ' ' +
                str(res.get('error') or ''))

    async def c_lock(self, peer):
        """S-05: `remote.lock` is a read (params {}, result {}, no idem) that ends this device's unlock at once."""
        require('remote.lock' in self.methods, 'welcome.methods lacks remote.lock (S-05, accepted by claude-w at 10:49)')
        try:
            res = await peer.request('remote.lock', {})
            require(res.get('ok') is True and res.get('result') == {},
                    'remote.lock: expected ok with {}, got ' + describe(res) + ' ' + str(res.get('result'))[:40])
            after = await peer.act('model_profiles', {})
            require(after.get('code') == 'unlock_required',
                    'after remote.lock the next call that acts: got ' + describe(after) + ', expected unlock_required')
            again = await peer.request('remote.lock', {})  # already locked: it still answers {}
            require(again.get('ok') is True and again.get('result') == {},
                    'remote.lock when already locked: ' + describe(again))
        finally:
            await self.reunlock(peer)
        return 'remote.lock answered {}, the next call needed the unlock, and it was unlocked again with a proof'

    async def c_last_connection(self):
        """S-05: a device's unlock also ends when its last connection closes (a phone that is gone is locked)."""
        first = await self.peer('K')
        welcome = await first.hello()
        require(welcome is not None and welcome.get('t') == 'welcome', 'hello got ' + describe(welcome))
        await self.reunlock(first)
        before = await first.act('model_profiles', {})
        require(before.get('ok') is True, 'model_profiles with the unlock: ' + describe(before))
        await first.close()  # the device's last connection
        await asyncio.sleep(0.4)
        second = await self.peer('K2')
        welcome = await second.hello()
        require(welcome is not None and welcome.get('t') == 'welcome', 'hello got ' + describe(welcome))
        after = await second.act('model_profiles', {})
        require(after.get('code') == 'unlock_required',
                "the unlock outlived the device's last connection: " + describe(after))
        return 'the unlock was gone on the next connection'

    # -- checks: resume, replay, events -------------------------------------------------------------------------------

    async def c_resume(self, peer, out):
        key = new_idem()
        sent = await peer.request('send', {'id': self.chat_id, 'text': MESSAGE}, idem=key)
        require(sent.get('ok') is True and isinstance(sent.get('result'), dict),
                'send: ' + describe(sent) + ' ' + str(sent.get('error')))
        result = sent['result']
        run_id = result.get('run_id')
        last = peer.last_seq(peer.welcome['seq'])
        events = {f['seq']: f for f in peer.events() if type(f.get('seq')) is int and f['seq'] <= last}
        await peer.close()
        await asyncio.sleep(1.0)
        later = await self.peer('E')
        welcome = await later.hello(resume={'epoch': self.epoch, 'seq': last})
        require(welcome is not None and welcome.get('t') == 'welcome', 'hello with resume got ' + describe(welcome))
        require(welcome.get('resumed') is True, 'resumed is false for an epoch and seq the bridge should still hold')
        require(type(welcome.get('seq')) is int and welcome['seq'] >= last, 'welcome.seq went backwards')
        missed = welcome['seq'] - last
        require(missed >= 1, 'inconclusive: no event happened while the phone was away')
        found = await later.wait(lambda f: f.get('t') == 'evt' and f.get('seq') == welcome['seq'], self.timeout)
        require(found is not None, 'the missed events were not all replayed')
        replayed = [f for f in later.frames if f.get('t') == 'evt'][:missed]
        seqs = [f.get('seq') for f in replayed]
        require(seqs == list(range(last + 1, welcome['seq'] + 1)),
                'replayed seq %s, expected %d..%d in order' % (seqs[:6], last + 1, welcome['seq']))
        first_index = next(i for i, f in enumerate(later.frames) if f.get('t') == 'evt')
        welcome_index = next(i for i, f in enumerate(later.frames) if f.get('t') == 'welcome')
        require(welcome_index < first_index, 'an event came before welcome')
        repeat = await later.request('send', {'id': self.chat_id, 'text': MESSAGE}, idem=key)
        if repeat.get('code') == 'unlock_required':  # S-05: the unlock ended with the first connection; ask again
            await self.reunlock(later)
            repeat = await later.request('send', {'id': self.chat_id, 'text': MESSAGE}, idem=key)
        require(repeat.get('ok') is True and repeat.get('result') == result,
                'the send repeat on a new connection did not return the first answer')
        settled = await later.wait(
            lambda f: f.get('t') == 'evt' and isinstance(f.get('data'), dict) and f['data'].get('run_id') == run_id
            and (f.get('event') == 'idle' or (f.get('event') == 'run' and f['data'].get('state') in SETTLED)),
            self.run_timeout)
        require(settled is not None, "the run did not finish within %d s" % self.run_timeout)
        await later.wait(lambda f: f.get('t') == 'evt' and f.get('event') == 'idle' and
                         isinstance(f.get('data'), dict) and f['data'].get('run_id') == run_id, 3)
        chat = await later.request('get_chat', {'id': self.chat_id})
        require(chat.get('ok') is True, 'get_chat: ' + describe(chat))
        sent_count = sum(1 for m in chat['result'].get('messages', [])
                         if m.get('role') == 'user' and m.get('content') == MESSAGE)
        require(sent_count == 1, 'the message is in the conversation %d times' % sent_count)
        for frame in later.events():
            if type(frame.get('seq')) is int:
                events.setdefault(frame['seq'], frame)
        out.update(peer=later, events=events, last=last, run_id=run_id, chat=chat['result'])
        return '%d missed events replayed; the repeat acted once' % missed

    async def c_replay(self, peer):
        require(self.unlock_frame is not None, 'no accepted proof to replay')
        res = await peer.exchange(dict(self.unlock_frame))
        require(res.get('ok') is False and res.get('code') == 'bad_proof',
                'the accepted remote.unlock frame, sent again on a new connection: ' + describe(res))
        moved = dict(self.unlock_frame, id=peer.next_id())
        res = await peer.exchange(moved)
        require(res.get('ok') is False and res.get('code') == 'bad_proof',
                'the same proof under a new request id: ' + describe(res))
        return 'verbatim and under a new id'

    async def c_events(self, resumed):
        events, chat = resumed['events'], resumed['chat']
        seqs = sorted(events)
        later = resumed['peer']
        live = [f.get('seq') for f in later.events()]
        require(live == sorted(set(live)) and all(b == a + 1 for a, b in zip(live, live[1:])),
                'seq on the resumed connection is not consecutive: %s' % live[:12])
        for seq in seqs:
            frame = events[seq]
            require(isinstance(frame.get('event'), str) and isinstance(frame.get('data'), (dict, list)) and
                    is_ms(frame.get('ts'), wire.now_ms()), 'event %d lacks event, data or ts (unix ms)' % seq)
        run_events = [events[s] for s in seqs if events[s].get('event') == 'run' and
                      isinstance(events[s].get('data'), dict) and events[s]['data'].get('run_id') == resumed['run_id']]
        require(run_events and all(isinstance(e['data'].get('chat_id'), str) and isinstance(e['data'].get('state'), str)
                                   for e in run_events), 'no run event {chat_id, run_id, state} for the run')
        activity = [events[s] for s in seqs if events[s].get('event') == 'activity' and
                    isinstance(events[s].get('data'), dict) and events[s]['data'].get('run_id') == resumed['run_id']]
        require(activity, 'no activity event for the run: C4 forwards every event the main window gets')
        require(all(isinstance(e['data'].get('item'), dict) for e in activity), 'an activity event has no item')
        tokens = [events[s] for s in seqs if events[s].get('event') == 'token' and
                  isinstance(events[s].get('data'), dict) and events[s]['data'].get('chat_id') == self.chat_id]
        replies = [m for m in chat.get('messages', []) if m.get('role') == 'assistant']
        detail = '%d events, %d activity' % (len(seqs), len(activity))
        if tokens and replies:
            require(all(isinstance(t['data'].get('id'), str) and isinstance(t['data'].get('text'), str)
                        for t in tokens), 'a token event lacks {chat_id, id, text}')
            reply = replies[-1]
            joined = ''.join(t['data']['text'] for t in tokens if t['data']['id'] == reply.get('id'))
            require(joined.strip() == str(reply.get('content', '')).strip(),
                    "the reply's token events do not join to its saved text")
            detail += ', %d token events join to the saved reply' % len(tokens)
        return detail

    async def c_times(self, main):
        now = wire.now_ms()
        row = self.device_row
        require(is_ms(row.get('paired_at'), now) and is_ms(row.get('last_seen'), now),
                'remote.devices paired_at/last_seen are not unix ms')
        require(is_ms(main.challenge.get('time'), now), 'challenge.time is not unix ms')
        require(is_ms(self.unlocked_until), 'unlocked_until is not unix ms')
        seen = [f for p in self.peers for f in p.events() if f.get('event') == 'remote.devices']
        if not seen:
            return 'times are unix ms; no remote.devices event was seen to check'
        data = seen[0].get('data')
        rows = data.get('devices') if isinstance(data, dict) else data
        require(isinstance(rows, list) and any(isinstance(d, dict) and d.get('device_id') == self.phone.device_id
                                               for d in rows),
                'the remote.devices event does not carry the device array')
        require(all(is_ms(d.get('paired_at'), now) for d in rows if isinstance(d, dict)),
                'the remote.devices event has times that are not unix ms')
        return 'times are unix ms; the remote.devices event carries the array'

    # -- checks: one connection per device, limits, screenshots -------------------------------------------------------

    async def c_stale_epoch(self, out):
        peer = await self.peer('F')
        welcome = await peer.hello(resume={'epoch': 'e-stale-' + uuid.uuid4().hex[:8], 'seq': 1})
        require(welcome is not None and welcome.get('t') == 'welcome', 'hello got ' + describe(welcome))
        out['peer'] = peer
        require(welcome.get('resumed') is False, 'resumed is true for an epoch the bridge never had')
        return ''

    async def c_replaced(self, older, newer):
        found = await older.wait(lambda f: f.get('t') == 'bye', 3)
        require(found is not None, 'the older connection got no bye')
        require(found[1].get('code') == 'replaced', 'the older connection got ' + describe(found[1]))
        require(isinstance(found[1].get('error'), str) and found[1]['error'], 'bye has no words for the person')
        require(await older.wait_closed(3), 'the older connection was not closed')
        res = await newer.request('remote.ping', {'ts': wire.now_ms()})
        require(res.get('ok') is True, 'the newer connection does not work: ' + describe(res))
        return ''

    async def c_too_large(self, peer):
        limit = self.limits.get('max_request', 131072)
        res = await peer.request('chat_search', {'query': 'x' * (limit + 2048)}, request_id='too-large-1')
        require(res.get('ok') is False and res.get('code') == 'too_large', describe(res))
        after = await peer.request('remote.ping', {'ts': wire.now_ms()})
        require(after.get('ok') is True, 'the connection did not survive the refusal: ' + describe(after))
        return '%d bytes refused; the connection stays' % (limit + 2048)

    async def c_websocket(self, peer):
        rtt = await peer.ws.ping(b'conformance')
        stamp = wire.now_ms()
        frame = json.dumps({'t': 'req', 'id': 'fragmented-1', 'method': 'remote.ping', 'params': {'ts': stamp}},
                           separators=(',', ':')).encode()
        third = len(frame) // 3
        await self.pacer.take()
        await peer.ws.send_frame(wire.OP_TEXT, frame[:third], fin=False)
        await peer.ws.send_frame(wire.OP_PING, b'between')
        await peer.ws.send_frame(wire.OP_CONT, frame[third:2 * third], fin=False)
        await peer.ws.send_frame(wire.OP_CONT, frame[2 * third:], fin=True)
        found = await peer.wait(lambda f: f.get('t') == 'res' and f.get('id') == 'fragmented-1', self.timeout)
        require(found is not None and found[1].get('ok') is True and found[1]['result'].get('ts') == stamp,
                'the fragmented request got ' + describe(found and found[1]))
        return 'round trip %.1f ms' % (rtt * 1000)

    async def c_screenshot(self, peer):
        if not self.screenshot:
            raise Skipped('--no-screenshot')
        if 'remote.screenshot' not in self.methods:
            raise Skipped('remote.screenshot is not offered')
        res = await peer.request('remote.screenshot', {'display': None})
        if res.get('ok') is False and res.get('code') not in BRIDGE_CODES and res.get('error'):
            return 'the Mac refused in words (Screen Recording off?); nothing to check'
        require(res.get('ok') is True and isinstance(res.get('result'), dict), describe(res))
        result = res['result']
        require(is_ms(result.get('taken_at'), wire.now_ms()), 'taken_at is not unix ms')
        displays = result.get('displays')
        require(isinstance(displays, list) and displays, 'no displays')
        for display in displays:
            require(isinstance(display, dict) and type(display.get('index')) is int and
                    display.get('format') == 'jpeg', 'a display lacks index or format jpeg')
            try:
                jpeg = base64.b64decode(display.get('data') or '', validate=True)
                size = wire.jpeg_size(jpeg)
            except ValueError:
                raise CheckFailed('display %s data is not a base64 JPEG' % display.get('index')) from None
            require(size == (display.get('width'), display.get('height')),
                    'display %d: the JPEG is %dx%d, not the width and height given' % ((display['index'],) + size))
            require(max(size) <= LONG_SIDE, 'display %d: the long side is over 2,560 px' % display['index'])
        first = displays[0]['index']
        one = await peer.request('remote.screenshot', {'display': first})
        require(one.get('ok') is True and [d.get('index') for d in one['result'].get('displays', [])] == [first],
                'asking for display %d did not give just that display' % first)
        absent = max(d['index'] for d in displays) + 7
        none = await peer.request('remote.screenshot', {'display': absent})
        require(none.get('ok') is False and none.get('error'), 'a display that does not exist was not refused')
        return '%d displays: %s' % (len(displays), ', '.join('%dx%d' % (d['width'], d['height']) for d in displays))

    async def c_rate_limit(self, peer):
        await asyncio.sleep(2.2)  # let the bridge's bucket fill
        frames = [{'t': 'req', 'id': 'burst-%d' % i, 'method': 'remote.ping', 'params': {'ts': i}} for i in range(40)]
        start = len(peer.frames)
        for frame in frames:
            await peer.send(frame)
        found = await peer.wait(lambda f: f.get('t') == 'res' and f.get('id') == 'burst-39', self.timeout, start)
        require(found is not None, 'the burst was not answered')
        answers = [f for f in peer.frames[start:] if f.get('t') == 'res' and str(f.get('id')).startswith('burst-')]
        limited = sum(1 for f in answers if f.get('code') == 'rate_limited')
        passed = sum(1 for f in answers if f.get('ok') is True)
        require(limited >= 1, 'no request of a burst of 40 was rate_limited')
        require(passed >= 15, 'only %d of 40 were answered before the limit' % passed)
        await asyncio.sleep(2.2)
        self.pacer = Pacer()
        return '%d answered, %d rate_limited' % (passed, limited)

    async def c_unreadable(self, peer):
        limit = self.limits.get('max_request', 131072)
        start = len(peer.frames)
        await peer.ws.send_text('{"t":"req","id":"unreadable-1","method":"state","params":{"pad":"' +
                                'x' * (limit + 2048))  # never closed: it cannot parse
        found = await peer.wait(lambda f: f.get('t') in ('bye', 'res'), self.timeout, start)
        require(found is not None and found[1].get('t') == 'bye' and found[1].get('code') == 'too_large',
                'an unreadable frame over max_request got ' + describe(found and found[1]))
        require(await peer.wait_closed(3), 'the connection stayed open after bye too_large')
        return ''

    async def c_unknown_device(self):
        peer = await self.peer('G')
        answer = await peer.hello(device_id='d-unknown-' + uuid.uuid4().hex[:12])
        require(answer is not None and answer.get('t') == 'bye' and answer.get('code') == 'unknown_device',
                'got ' + describe(answer))
        require(await peer.wait_closed(3), 'the connection stayed open after bye')
        return ''

    async def c_deep_request(self):
        """Frames nested far deeper than any parser should follow: 20,000 levels in 40 KB (under max_request), then
        300,000 levels in 600 KB (over it, for a bridge that parses before it measures). A parser that recursed that far
        would crash the bridge, and Pebble's shell with it. The bridge may answer or close each connection, but must
        keep serving. remote.ping is the bridge's own method, so nothing reaches Pebble even if it parses."""
        answers = []
        for depth in (20000, 300000):
            peer = await self.peer('J%d' % depth)
            welcome = await peer.hello()
            require(welcome is not None and welcome.get('t') == 'welcome', 'hello got ' + describe(welcome))
            start = len(peer.frames)
            await self.pacer.take()
            try:
                await peer.ws.send_text('{"t":"req","id":"deep-1","method":"remote.ping","params":{"ts":1,"pad":' +
                                        '[' * depth + ']' * depth + '}}')
            except (ConnectionError, OSError):
                pass  # closed while it was being sent: also an answer
            found = await peer.wait(lambda f: f.get('t') in ('res', 'bye'), self.timeout, start)
            answers.append('closed' if found is None else describe(found[1]))
            await peer.close()
        after = await self.peer('J2')
        welcome = await after.hello()
        require(welcome is not None and welcome.get('t') == 'welcome',
                'after the deep requests no new connection was welcomed: ' + describe(welcome))
        res = await after.request('remote.ping', {'ts': wire.now_ms()})
        require(res.get('ok') is True, 'after the deep requests: ' + describe(res))
        await after.close()
        return 'answers: %s; still serving' % ', '.join(answers)

    async def c_revoke(self):
        peer = await self.peer('H')
        welcome = await peer.hello()
        require(welcome is not None and welcome.get('t') == 'welcome', 'hello got ' + describe(welcome))
        await self.reunlock(peer)  # S-05: the unlock ended with the device's last connection
        res = await peer.act('remote.revoke_device', {'device_id': self.phone.device_id})
        require(res.get('ok') is True, 'remote.revoke_device: ' + describe(res))
        found = await peer.wait(lambda f: f.get('t') == 'bye', 3)
        require(found is not None and found[1].get('code') == 'revoked',
                'revoking itself did not end the connection with bye revoked: ' + describe(found and found[1]))
        require(await peer.wait_closed(3), 'the connection stayed open')
        after = await self.peer('H2')
        answer = await after.hello()
        require(answer is not None and answer.get('t') == 'bye' and answer.get('code') in ('revoked', 'unknown_device'),
                'the removed key still connects: ' + describe(answer))
        return 'removed from the Mac; its key is refused'

    # -- checks: LAN exposure (C6) -------------------------------------------------------------------------------------

    async def c_handshake_limit(self):
        if self.loopback:
            raise Skipped('loopback is exempt; run against a LAN endpoint (--endpoint <LAN address>:<port>)')
        refused = None
        for attempt in range(12):
            peer = Peer(self, 'L%d' % attempt)  # deliberately unpaced
            try:
                await peer.connect()
            except CheckFailed as exc:
                refused = str(exc)
                break
            finally:
                await peer.close()
        require(refused is not None, 'twelve handshakes in a row within a minute were all accepted')
        return 'refused: ' + refused[:60]

    async def c_bonjour(self):
        if not self.bonjour:
            raise Skipped('pass --bonjour to resolve the advertised instance with dns-sd')
        process = await asyncio.create_subprocess_exec(
            '/usr/bin/dns-sd', '-L', self.link['bid'], '_pebble-remote._tcp', 'local',
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL, stdin=asyncio.subprocess.DEVNULL)
        text = ''
        try:
            deadline = time.monotonic() + 6
            while time.monotonic() < deadline and 'bid=' not in text:
                try:
                    line = await asyncio.wait_for(process.stdout.readline(), deadline - time.monotonic())
                except (asyncio.TimeoutError, TimeoutError):
                    break
                if not line:
                    break
                text += line.decode('utf-8', 'replace')
        finally:
            process.kill()
            await process.wait()
        require('can be reached at' in text, 'no _pebble-remote._tcp instance named %s answered' % self.link['bid'])
        require(':%d ' % self.endpoint[1] in text or ':%d\n' % self.endpoint[1] in text,
                'the instance names another port')
        require('bid=' + self.link['bid'] in text and 'v=1' in text, 'the TXT record lacks v=1 or bid=')
        return 'instance %s resolves with v=1 and bid' % self.link['bid']


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Check a Pebble Remote bridge against contract v0.3, proposal v0.5 when it offers remote.folders, '
                    'and proposal v0.6 when it offers remote.folder_create.')
    parser.add_argument('--link', required=True, help='a fresh pairing link (pebble-remote://pair?...)')
    parser.add_argument('--endpoint', help='host:port to use instead of the first endpoint in the link that answers')
    parser.add_argument('--timeout', type=float, default=10.0, help='seconds to wait for each answer')
    parser.add_argument('--run-timeout', type=float, default=120.0, help="seconds to wait for the test run's end")
    parser.add_argument('--keep-device', action='store_true', help='do not remove the paired test device at the end')
    parser.add_argument('--no-screenshot', action='store_true', help='skip the remote.screenshot check (C3)')
    parser.add_argument('--no-connect', action='store_true',
                        help='v0.5: do not connect a folder with a proof (the check that changes a conversation)')
    parser.add_argument('--no-link-probe', action='store_true',
                        help='v0.5: do not make two links in the home folder to try the link rule (only done on '
                             'loopback, and removed again at once)')
    parser.add_argument('--no-create-probe', action='store_true',
                        help='v0.6: do not ask the bridge for empty folders in the home folder to try '
                             'remote.folder_create (only done on loopback, and removed again at once)')
    parser.add_argument('--pair-wait', type=float, default=130.0, metavar='SECONDS',
                        help='X-1: how long to wait for the person to confirm the pairing code on the Mac (the bridge '
                             'gives up after two minutes; default 130)')
    parser.add_argument('--expect-pair-refused', action='store_true',
                        help='X-1: check a refusal instead: cancel the pairing on the Mac (or leave it unanswered) and '
                             'the checker expects bye bad_code and a spent code; run it besides the normal run')
    parser.add_argument('--bonjour', action='store_true', help='also resolve the Bonjour instance (C6) with dns-sd')
    parser.add_argument('--json', help='also write the results to this file as JSON')
    parser.add_argument('--verbose', action='store_true', help='print every frame received (content-free)')
    args = parser.parse_args(argv)
    try:
        endpoint = wire.parse_endpoint(args.endpoint) if args.endpoint else None
        checker = Checker(args.link, endpoint, args.timeout, args.run_timeout, args.verbose, args.keep_device,
                          screenshot=not args.no_screenshot, bonjour=args.bonjour, connect=not args.no_connect,
                          pair_wait=args.pair_wait, expect_pair_refused=args.expect_pair_refused,
                          link_probe=not args.no_link_probe, create_probe=not args.no_create_probe)
    except ValueError as exc:
        print('conformance: ' + str(exc), file=sys.stderr)
        return 2
    ok = asyncio.run(checker.run())
    if args.json:
        with open(args.json, 'w') as handle:
            json.dump({'ok': ok, 'results': checker.results}, handle, indent=1)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
