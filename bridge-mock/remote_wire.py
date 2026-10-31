"""Pebble Remote wire helpers, shared by the mock bridge and the conformance checker. Python standard library only.

- base64url without padding;
- ECDSA P-256 with SHA-256 in pure Python: verification, and signing with RFC 6979 deterministic k; strict DER;
- the pin of a certificate: base64url(SHA-256(DER SubjectPublicKeyInfo));
- the signed transcripts T_pair, T_hello and T_proof;
- the pairing link;
- a minimal RFC 6455 WebSocket over asyncio streams, for the server and the client role;
- the contract's tables (3.6, 3.7, C1, and v0.5's opening methods) and Pebble's protected-folder list;
- proposal v0.6's rules for the name of a new folder.

Contract: the bridge contract, sections 3 and 4, proposal v0.5 (section 6, 10:50) and proposal
v0.6 (section 6, 15:14).

The curve arithmetic is not constant time. Verifying a signature handles public data only, so that is safe; signing
here is for test keys (the conformance checker's software "phone"), never for a key that protects anything.
"""

import asyncio
import base64
import hashlib
import hmac
import os
import posixpath
import re
import secrets
import time
import unicodedata
from urllib.parse import quote, unquote

# ---------------------------------------------------------------------------------------------------------------------
# base64url

_B64U = re.compile(r'[A-Za-z0-9_-]*')


def b64u(data):
    """base64url without padding."""
    return base64.urlsafe_b64encode(bytes(data)).rstrip(b'=').decode('ascii')


def b64u_decode(text):
    """Strict base64url without padding: only the URL alphabet, no '=', no impossible length. Raises ValueError."""
    if not isinstance(text, str) or not _B64U.fullmatch(text) or len(text) % 4 == 1:
        raise ValueError('not base64url')
    data = base64.urlsafe_b64decode(text + '=' * (-len(text) % 4))
    if b64u(data) != text:  # non-zero padding bits: one value, one spelling
        raise ValueError('not canonical base64url')
    return data


def sha256(data):
    return hashlib.sha256(data).digest()


# ---------------------------------------------------------------------------------------------------------------------
# P-256 (secp256r1, prime256v1): SEC 2 / FIPS 186-4 domain parameters

P = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
A = P - 3
B = 0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b
N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
GX = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296
GY = 0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5
G = (GX, GY)

# DER SubjectPublicKeyInfo of a P-256 key = this fixed prefix + the 65-byte X9.63 point:
# SEQUENCE { SEQUENCE { OID ecPublicKey, OID prime256v1 }, BIT STRING (0 unused bits) }
SPKI_P256_PREFIX = bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d030107034200')


def on_curve(point):
    x, y = point
    return 0 <= x < P and 0 <= y < P and (y * y - (x * x * x + A * x + B)) % P == 0


# Jacobian coordinates (X, Y, Z) stand for the affine point (X/Z^2, Y/Z^3). None is the point at infinity.

def _jdouble(pt):
    if pt is None:
        return None
    x1, y1, z1 = pt
    if y1 == 0:
        return None
    yy = y1 * y1 % P
    s = 4 * x1 * yy % P
    zz = z1 * z1 % P
    m = 3 * (x1 - zz) * (x1 + zz) % P  # 3X^2 + aZ^4 with a = -3
    x3 = (m * m - 2 * s) % P
    y3 = (m * (s - x3) - 8 * yy * yy) % P
    z3 = 2 * y1 * z1 % P
    return (x3, y3, z3)


def _jadd(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1, z1 = p1
    x2, y2, z2 = p2
    z1z1 = z1 * z1 % P
    z2z2 = z2 * z2 % P
    u1 = x1 * z2z2 % P
    u2 = x2 * z1z1 % P
    s1 = y1 * z2 * z2z2 % P
    s2 = y2 * z1 * z1z1 % P
    if u1 == u2:
        if s1 != s2:
            return None  # P + (-P)
        return _jdouble(p1)
    h = (u2 - u1) % P
    r = (s2 - s1) % P
    hh = h * h % P
    hhh = h * hh % P
    v = u1 * hh % P
    x3 = (r * r - hhh - 2 * v) % P
    y3 = (r * (v - x3) - s1 * hhh) % P
    z3 = h * z1 * z2 % P
    return (x3, y3, z3)


def _affine(pt):
    if pt is None:
        return None
    x, y, z = pt
    zi = pow(z, -1, P)
    zi2 = zi * zi % P
    return (x * zi2 % P, y * zi2 * zi % P)


def point_mul(k, point):
    """k * point (affine in, affine out; None for infinity). Left-to-right double-and-add."""
    k %= N
    if k == 0 or point is None:
        return None
    q = (point[0], point[1], 1)
    acc = None
    for bit in bin(k)[2:]:
        acc = _jdouble(acc)
        if bit == '1':
            acc = _jadd(acc, q)
    return _affine(acc)


def _mul_add(u1, u2, q):
    """u1*G + u2*Q in one pass (Shamir's trick); Jacobian result."""
    g = (GX, GY, 1)
    qj = (q[0], q[1], 1)
    gq = _jadd(g, qj)
    acc = None
    for i in range(max(u1.bit_length(), u2.bit_length()) - 1, -1, -1):
        acc = _jdouble(acc)
        b1, b2 = (u1 >> i) & 1, (u2 >> i) & 1
        if b1 and b2:
            acc = _jadd(acc, gq)
        elif b1:
            acc = _jadd(acc, g)
        elif b2:
            acc = _jadd(acc, qj)
    return acc


def encode_point(point):
    """X9.63 uncompressed: 0x04 || X || Y (65 bytes)."""
    return b'\x04' + point[0].to_bytes(32, 'big') + point[1].to_bytes(32, 'big')


def decode_point(data):
    """65-byte X9.63 uncompressed point, checked to lie on P-256. Raises ValueError."""
    if not isinstance(data, (bytes, bytearray)) or len(data) != 65 or data[0] != 4:
        raise ValueError('not an uncompressed P-256 point')
    point = (int.from_bytes(data[1:33], 'big'), int.from_bytes(data[33:], 'big'))
    if not on_curve(point):
        raise ValueError('point is not on P-256')
    return point


def spki_der(point):
    return SPKI_P256_PREFIX + encode_point(point)


def public_key_pem(point):
    body = base64.encodebytes(spki_der(point)).decode('ascii').replace('\n', '')
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return '-----BEGIN PUBLIC KEY-----\n' + '\n'.join(lines) + '\n-----END PUBLIC KEY-----\n'


# ---------------------------------------------------------------------------------------------------------------------
# DER

def _der_length(buf, pos, max_bytes=4):
    if pos >= len(buf):
        raise ValueError('truncated DER length')
    first = buf[pos]
    pos += 1
    if first < 0x80:
        return first, pos
    count = first & 0x7f
    if count == 0 or count > max_bytes or pos + count > len(buf):
        raise ValueError('bad DER length')
    value = int.from_bytes(buf[pos:pos + count], 'big')
    if value < 0x80 or value < (1 << (8 * (count - 1))):
        raise ValueError('non-minimal DER length')
    return value, pos + count


def der_next(buf, pos):
    """One DER element at pos: (tag, value_start, value_end). Single-byte tags only."""
    if pos >= len(buf):
        raise ValueError('truncated DER')
    tag = buf[pos]
    if tag & 0x1f == 0x1f:
        raise ValueError('multi-byte DER tags are not used here')
    length, start = _der_length(buf, pos + 1)
    end = start + length
    if end > len(buf):
        raise ValueError('truncated DER value')
    return tag, start, end


def _der_uint(buf, pos):
    tag, start, end = der_next(buf, pos)
    if tag != 0x02 or end == start or end - start > 33:
        raise ValueError('bad DER INTEGER')
    body = buf[start:end]
    if body[0] & 0x80:
        raise ValueError('negative DER INTEGER')
    if len(body) > 1 and body[0] == 0 and not body[1] & 0x80:
        raise ValueError('non-minimal DER INTEGER')
    return int.from_bytes(body, 'big'), end


def _der_int_bytes(value):
    body = value.to_bytes(value.bit_length() // 8 + 1, 'big')  # a leading 0x00 when the top bit is set
    return b'\x02' + bytes([len(body)]) + body


def der_encode_signature(r, s):
    body = _der_int_bytes(r) + _der_int_bytes(s)
    return b'\x30' + bytes([len(body)]) + body


def der_decode_signature(sig):
    """Strict DER ECDSA-Sig-Value: SEQUENCE { INTEGER r, INTEGER s }, minimal, nothing after it. Raises ValueError."""
    if not isinstance(sig, (bytes, bytearray)) or len(sig) < 8 or len(sig) > 72:
        raise ValueError('bad signature length')
    tag, start, end = der_next(sig, 0)
    if tag != 0x30 or end != len(sig):
        raise ValueError('bad signature sequence')
    r, pos = _der_uint(sig, start)
    s, pos = _der_uint(sig, pos)
    if pos != end:
        raise ValueError('trailing data in signature')
    return r, s


def spki_from_certificate(cert_der):
    """The DER SubjectPublicKeyInfo element (tag, length and value) of an X.509 certificate."""
    tag, start, end = der_next(cert_der, 0)
    if tag != 0x30:
        raise ValueError('not a certificate')
    tag, tbs_start, tbs_end = der_next(cert_der, start)
    if tag != 0x30:
        raise ValueError('no TBSCertificate')
    items, pos = [], tbs_start
    while pos < tbs_end and len(items) < 8:
        tag, value_start, value_end = der_next(cert_der, pos)
        items.append((tag, pos, value_end))
        pos = value_end
    first = 1 if items and items[0][0] == 0xa0 else 0  # [0] EXPLICIT version
    # serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
    if len(items) < first + 6 or items[first + 5][0] != 0x30:
        raise ValueError('no SubjectPublicKeyInfo')
    _, spki_start, spki_end = items[first + 5]
    return bytes(cert_der[spki_start:spki_end])


def spki_pin(spki):
    return b64u(sha256(spki))


def certificate_pin(cert_der):
    return spki_pin(spki_from_certificate(cert_der))


def sec1_private_scalar(der):
    """The private scalar of a SEC 1 ECPrivateKey (DER), for tests: SEQUENCE { INTEGER 1, OCTET STRING d, ... }."""
    tag, start, end = der_next(der, 0)
    if tag != 0x30:
        raise ValueError('not an ECPrivateKey')
    version, pos = _der_uint(der, start)
    tag, value_start, value_end = der_next(der, pos)
    if version != 1 or tag != 0x04:
        raise ValueError('not an ECPrivateKey')
    return int.from_bytes(der[value_start:value_end], 'big')


# ---------------------------------------------------------------------------------------------------------------------
# ECDSA with SHA-256

def verify(public_point, message, signature_der):
    """True when signature_der is a valid DER ECDSA P-256/SHA-256 signature of message by public_point.

    Accepts high-s signatures (the contract does not require low-s). Never raises for bad input."""
    try:
        r, s = der_decode_signature(signature_der)
        if public_point is None or not on_curve(public_point):
            return False
    except (ValueError, TypeError):
        return False
    if not (1 <= r < N and 1 <= s < N):
        return False
    e = int.from_bytes(sha256(message), 'big')
    w = pow(s, -1, N)
    total = _mul_add(e * w % N, r * w % N, public_point)
    if total is None:
        return False
    return _affine(total)[0] % N == r


def _hmac(key, data):
    return hmac.new(key, data, hashlib.sha256).digest()


def rfc6979_nonces(private, digest):
    """RFC 6979 section 3.2 candidate nonces for P-256 and HMAC-SHA-256 (qlen = hlen = 256 bits)."""
    x = private.to_bytes(32, 'big')
    h = (int.from_bytes(digest, 'big') % N).to_bytes(32, 'big')  # bits2octets
    v = b'\x01' * 32
    k = b'\x00' * 32
    k = _hmac(k, v + b'\x00' + x + h)
    v = _hmac(k, v)
    k = _hmac(k, v + b'\x01' + x + h)
    v = _hmac(k, v)
    while True:
        v = _hmac(k, v)
        candidate = int.from_bytes(v, 'big')
        if 1 <= candidate < N:
            yield candidate
        k = _hmac(k, v + b'\x00')
        v = _hmac(k, v)


def sign_rs(private, message):
    """(r, s) with RFC 6979 deterministic k."""
    digest = sha256(message)
    e = int.from_bytes(digest, 'big')
    for k in rfc6979_nonces(private, digest):
        point = point_mul(k, G)
        r = point[0] % N
        if r == 0:
            continue
        s = pow(k, -1, N) * (e + r * private) % N
        if s != 0:
            return r, s


def sign(private, message):
    """DER ECDSA P-256/SHA-256 signature of message (RFC 6979)."""
    return der_encode_signature(*sign_rs(private, message))


class SigningKey:
    """A software P-256 key: the conformance checker's stand-in for the iPhone's Secure Enclave keys."""

    def __init__(self, private=None):
        self.private = private if private is not None else secrets.randbelow(N - 1) + 1
        if not 1 <= self.private < N:
            raise ValueError('private scalar out of range')
        self.public = point_mul(self.private, G)

    @property
    def x963(self):
        return encode_point(self.public)

    @property
    def x963_b64u(self):
        return b64u(self.x963)

    def sign(self, message):
        return sign(self.private, message)


# ---------------------------------------------------------------------------------------------------------------------
# Transcripts (section 3.2, 3.3, 3.6): lines, each followed by "\n", UTF-8.

def _lines(*parts):
    for part in parts:
        if not isinstance(part, str) or '\n' in part:
            raise ValueError('a transcript line must be one line of text')
    return ''.join(part + '\n' for part in parts).encode('utf-8')


def t_pair(bid, nonce, pin, code, device_key, approve_key):
    return _lines('pebble-remote/v1/pair', bid, nonce, pin, code, device_key, approve_key)


def t_hello(bid, device_id, nonce, pin):
    return _lines('pebble-remote/v1/hello', bid, device_id, nonce, pin)


def t_proof(bid, device_id, epoch, nonce, request_id, idem, method, params_json, ts):
    """T_proof v0.3 (section 3.11 item 3): bound to this connection's challenge nonce and to the call's idem."""
    if type(ts) is not int or ts < 0:
        raise ValueError('ts must be a non-negative whole number of milliseconds')
    return _lines('pebble-remote/v1/proof', bid, device_id, epoch, nonce, request_id, idem, method,
                  b64u(sha256(params_json.encode('utf-8'))), str(ts))


def t_proof_v02(bid, device_id, epoch, request_id, method, params_json, ts):
    """T_proof as contract v0.2 had it (no nonce, no idem): only for the mock's --proof-version 2 transition."""
    if type(ts) is not int or ts < 0:
        raise ValueError('ts must be a non-negative whole number of milliseconds')
    return _lines('pebble-remote/v1/proof', bid, device_id, epoch, request_id, method,
                  b64u(sha256(params_json.encode('utf-8'))), str(ts))


# X-1 (claude-w's answer of 2026-10-30 10:49, item 3): after `pair` verifies, the Mac and the phone both show a short
# code, and the bridge sends `paired` only after the person confirms on the Mac that the two codes match. Cancel, or two
# minutes without an answer, is `bye` `bad_code`, and the pairing code is spent.
SAS_LABEL = b'pebble-remote/v1/sas\n'
PAIR_CONFIRM_SECONDS = 120


def sas_code(t_pair):
    """The six digits both sides show: the first 4 bytes of SHA-256 over the UTF-8 bytes of "pebble-remote/v1/sas\n"
    followed by T_pair (the transcript the pair signatures cover, section 3.2), read as a big-endian unsigned integer,
    mod 1,000,000, zero-padded to 6 digits."""
    if not isinstance(t_pair, (bytes, bytearray)):
        raise ValueError('T_pair is bytes')
    return '%06d' % (int.from_bytes(sha256(SAS_LABEL + bytes(t_pair))[:4], 'big') % 1000000)


# Golden vectors for the formula, shared with the phone's lane: the fields of T_pair (bid, nonce, pin, code, device_key,
# approve_key), the SHA-256 over the label and T_pair, and the code. The first has a code that starts with a zero.
SAS_VECTORS = (
    {'fields': ('b-1', 'n-1', 'p-1', 'c-1', 'dk-1', 'ak-1'),
     'digest': '57065e008e6e8ae233d92ebd1b61315ad0cb083f1a2d2ec6f428b7d804b937b5', 'code': '035072'},
    {'fields': ('b-AAECAwQFBgcICQoL', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
                'uBxfZqYw5vyQji5sLR4Ex6QEFGKWKNk-v7nH6PPPyFM', 'ZGVmZ2hpamtsbW5vcHFycw',
                'BAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8',
                'BEBBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn8'),
     'digest': '9d6a609c86ea7ca392c70ae278859a96aa42ee081bf53e9f23339ab73dde43c6', 'code': '994460'},
)


# Section 3.11 item 2: request ids (and idem keys, which are T_proof lines too).
ID_CHARS = re.compile(r'[A-Za-z0-9_-]{1,64}')


def valid_id(value):
    return isinstance(value, str) and ID_CHARS.fullmatch(value) is not None


# ---------------------------------------------------------------------------------------------------------------------
# Contract tables (v0.3 and v0.5), shared by the mock and the checker

# Proposal v0.5 (R6; the iOS side's 2026-10-30 10:50, accepted by claude-w at 10:53): "opening things on the Mac's
# screen" moves from the excluded list to the allowed one, every method elevated (a Face ID proof on each call).
OPEN_ON_MAC = ('open_url', 'open_app', 'view_stage', 'artifact_view_open', 'browser_start', 'browser_open_tab',
               'quiz_share', 'terminal_propose', 'process_terminal')
# Proposal v0.5: `remote.folders` lists at most this many subfolders.
FOLDERS_LIMIT = 500
# Proposal v0.6 (the iOS side's 2026-10-30 15:14): `remote.folder_create {parent, name}` makes one empty folder. A folder
# this device made in the last MADE_FOLDER_SECONDS counts as known for this device: `set_workspace` and `new_chat
# {workspace}` with exactly its path need only the unlock.
FOLDER_NAME_BYTES = 255
MADE_FOLDER_SECONDS = 600

# Section 3.7 (v0.2): PHONE_ALLOWED = ALLOWED - PHONE_EXCLUDED; NATIVE_ONLY is never included.
PHONE_EXCLUDED_V03 = frozenset({
    # local files and pickers (set_workspace with a path no conversation uses is refused by the bridge's policy)
    'attach', 'model_save', 'model_save_many', 'model_remove', 'model_discover', 'set_model', 'memory_export',
    'memory_archive_export_to', 'memory_archive_preview_file', 'memory_archive_import_file', 'export_save',
    'git_export', 'git_export_file', 'media_download', 'telemetry_export', 'telemetry_clear', 'storage_reveal',
    'storage_set', 'storage_settings_resolve', 'storage_forget_resolve', 'storage_cleanup_legacy', 'storage_delete',
    # sign-ins and credentials (and every connector_* except connector_status)
    'chatgpt_start', 'chatgpt_cancel', 'chatgpt_sign_out', 'plan_credentials', 'plan_credential_save',
    'plan_credential_delete',
    # installing code (and every plugin_package_*)
    'mod_install', 'mod_example', 'mod_preview', 'mod_remove', 'extension_add', 'extension_import', 'extension_remove',
    'browser_connect_install',
    # opening things on the Mac's screen (v0.5 allows these, elevated)
    'open_url', 'open_app', 'view_stage', 'artifact_view_open', 'terminal_propose', 'process_terminal',
    'browser_start', 'browser_open_tab', 'quiz_share',
    # Mac maintenance and the browser profile
    'upgrade_backups', 'upgrade_discard_backup', 'upgrade_retry', 'browser_profile_forget', 'browser_extension_unpair',
})
# v0.5: the same table without the opening methods. Still Mac-only: sign-ins and credentials, installing code, and the
# file pickers for export and import.
PHONE_EXCLUDED = PHONE_EXCLUDED_V03 - frozenset(OPEN_ON_MAC)
# Pebble's src-tauri/src/main.rs NATIVE_ONLY: routes only the shell itself may call.
NATIVE_ONLY = frozenset({'lifecycle_event', 'lifecycle_quit_summary', 'notification_native_pending',
                         'notification_native_delivered', 'export_destination_bind', 'export_native_ready',
                         'export_pdf_attach', 'export_pdf_failed', 'telemetry_destination_bind'})


def phone_excluded(method, v05=True):
    """Whether section 3.7 keeps `method` off the phone. `v05=False` is the v0.3 table, which also kept the nine
    opening methods off (a bridge that offers `remote.folders` follows v0.5)."""
    table = PHONE_EXCLUDED if v05 else PHONE_EXCLUDED_V03
    return method in table or method in NATIVE_ONLY or method.startswith('plugin_package_') or (
        method.startswith('connector_') and method != 'connector_status')


# Section 3.6 (v0.2) plus C1's remote.unlock: calls that always carry a Face ID proof.
ELEVATED_ALWAYS = frozenset({
    'approve', 'approve_simple', 'run_held_accept', 'run_held_finish', 'model_handoff_approve',  # approvals
    'storage_purge_chat', 'storage_purge_all', 'storage_trash_all', 'delete_chat', 'memory_delete', 'memory_clear',
    'git_remove_worktree', 'agent_worktree_retire', 'environment_remove', 'rewind_apply',  # deletions
    'screen_session_grant', 'app_control_request', 'shell_grant_add', 'shell_grant_remove', 'extension_toggle',
    'mod_toggle', 'process_input_human',  # more reach
    'job_create', 'job_resume',  # work without the person
    'remote.unlock',  # C1
    'remote.folder_create',  # v0.6: it writes to the Mac's disk
}) | frozenset(OPEN_ON_MAC)  # v0.5: opening things on the Mac
# C1: what a connection may call without a recent Face ID proof from its device.
# S-05 (claude-w, 2026-10-30 10:49, item 4) adds `remote.lock` to the list: a read ({} to {}) that ends the unlock at once.
UNLOCK_FREE = frozenset({'state', 'get_chat', 'chat_search', 'run_list', 'run_get', 'run_activity', 'run_events',
                         'stream_read', 'artifact_get', 'remote.status', 'remote.devices', 'remote.ping',
                         'remote.chat_tail', 'remote.chat_before', 'remote.lock'})
# v0.3 item 4: idem goes on every call that is not read-only. These are the read-only ones (idem optional there).
# `remote.folders` (v0.5) is one of them, and needs the unlock all the same: it shows the Mac's folder names.
READ_ONLY = UNLOCK_FREE | frozenset({
    'model_profiles', 'screen_sessions', 'toolbox_list', 'toolbox_get', 'job_list', 'job_get', 'job_preview',
    'job_preview_resume', 'goal_list', 'goal_get', 'notification_status', 'command_catalogue', 'storage_summary',
    'browser_status', 'remote.screenshot', 'remote.folders'})
REMOTE_METHODS = ('remote.status', 'remote.devices', 'remote.revoke_device', 'remote.keep_awake', 'remote.chat_tail',
                  'remote.chat_before', 'remote.ping', 'remote.unlock', 'remote.screenshot', 'remote.folders',
                  'remote.lock', 'remote.folder_create')


# ---------------------------------------------------------------------------------------------------------------------
# Folders (v0.5): what `remote.folders` leaves out. Pebble's Shell sandbox's protected list, D92:
# backend/pebble/shell_policy.py (PROTECTED_HOME, PROTECTED_PREFIX, PROTECTED_NAME), copied here and compared with the
# Pebble checkout by test_mock.py when it is present. The checkout is only ever read.

# Paths relative to the home folder; each covers everything below it.
PROTECTED_HOME = (
    # keys and credentials
    '.ssh', '.gnupg', '.aws', '.azure', '.config/gcloud', '.kube', '.docker', '.netrc', '.npmrc', '.pypirc',
    '.git-credentials', '.config/gh', '.config/hub', '.config/op', '.vault-token', '.terraform.d', '.oci', '.s3cfg',
    '.boto', '.pgpass', '.my.cnf', '.config/rclone', '.cargo/credentials', '.cargo/credentials.toml',
    '.gem/credentials', '.m2/settings.xml', '.gradle/gradle.properties', '.config/heroku', '.config/configstore',
    'Library/Keychains',
    # password managers
    'Library/Group Containers/2BUA8C4S2C.com.1password', 'Library/Application Support/1Password',
    'Library/Containers/com.1password.1password', 'Library/Application Support/Bitwarden',
    'Library/Containers/com.bitwarden.desktop', 'Library/Application Support/KeePassXC',
    'Library/Application Support/Dashlane', 'Library/Application Support/Enpass',
    # browser data
    'Library/Safari', 'Library/Containers/com.apple.Safari', 'Library/Cookies', 'Library/HTTPStorages',
    'Library/WebKit', 'Library/Application Support/Google', 'Library/Application Support/Chromium',
    'Library/Application Support/BraveSoftware', 'Library/Application Support/Microsoft Edge',
    'Library/Application Support/Arc', 'Library/Application Support/Firefox', 'Library/Application Support/Vivaldi',
    'Library/Application Support/com.operasoftware.Opera', 'Library/Application Support/Comet',
    'Library/Application Support/Perplexity', 'Library/Application Support/Orion', 'Library/Caches/Google',
    'Library/Caches/BraveSoftware', 'Library/Caches/Firefox', 'Library/Caches/com.apple.Safari',
    # Messages and Mail
    'Library/Messages', 'Library/Containers/com.apple.MobileSMS', 'Library/Mail', 'Library/Containers/com.apple.mail',
    'Library/Group Containers/group.com.apple.mail',
    # Pebble's own data, signing and backups
    '.pebble', 'Documents/Pebble', 'PebbleBackups', 'Library/Application Support/com.pebble.local',
    # other agents' credentials and sessions
    '.claude', '.claude.json', '.codex', '.gemini', '.config/claude', '.config/github-copilot',
    '.cursor', '.continue',
    # shell and tool histories
    '.zsh_history', '.zsh_sessions', '.bash_history', '.bash_sessions', '.python_history', '.node_repl_history',
    '.psql_history', '.mysql_history', '.sqlite_history', '.irb_history', '.lesshst', '.local/share/fish',
    # macOS privacy databases and accounts
    'Library/Application Support/com.apple.TCC', 'Library/Accounts', 'Library/IdentityServices',
)
# Top-level home entries protected by their prefix: every Claude account folder, whatever its name.
PROTECTED_PREFIX = ('.claude',)
# Names that are secrets wherever they are.
PROTECTED_NAME = re.compile(
    r'(^|/)(\.env(\.[^/]*)?|\.envrc|credentials(\.json|\.toml|\.ya?ml)?|secrets?(\.json|\.toml|\.ya?ml)?'
    r'|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?|[^/]*\.(pem|key|p12|pfx|kdbx|keychain|keychain-db|ppk|jks|keystore)'
    r'|\.git-credentials|\.htpasswd|\.pgpass|\.dockercfg|kubeconfig|\.docker/config\.json|\.kube/config'
    r'|[^/]*\.tfstate(\.[^/]*)?|[^/]+\.env|[^/]*service[-_]account[^/]*\.json|client_secrets?[^/]*\.json)$',
    re.I)


def _inside(folded, base):
    return folded == base or folded.startswith(base.rstrip('/') + '/')


def protected_bases(home, extra_roots=(), realpath=os.path.realpath):
    """The protected list resolved against `home`, as `protected_entry` compares it. Resolving the whole list takes a
    few milliseconds, so a caller that judges many folders (a listing) makes this once and passes it as `bases`."""
    return {'home': realpath(home).casefold(),
            'entries': [('~/' + entry, realpath(posixpath.join(home, entry)).casefold()) for entry in PROTECTED_HOME],
            'extras': [(str(root), realpath(root).casefold()) for root in extra_roots]}


def protected_entry(home, path, extra_roots=(), realpath=os.path.realpath, exists=os.path.lexists, bases=None,
                    resolved=False):
    """The protected entry `path` falls under (Pebble's `shell_policy.protected_path`, D92), or None. Compared without
    regard to case, as APFS is by default. `extra_roots` are more folders to protect (the mock's own state folder).

    By default links are resolved and the disk is looked at, as Pebble does. The conformance checker judges the names
    a bridge sent, and must not touch its own disk: it passes `realpath=posixpath.normpath` and `exists=lambda p: True`.
    `bases` (from `protected_bases`) saves resolving the list again; `resolved` says `path` is already a real path."""
    bases = bases or protected_bases(home, extra_roots, realpath)
    real = path if resolved else realpath(path)
    folded = real.casefold()
    for entry, base in bases['entries']:
        if _inside(folded, base):
            return entry
    real_home = bases['home']
    if folded.startswith(real_home.rstrip('/') + '/'):
        top = folded[len(real_home.rstrip('/')) + 1:].split('/', 1)[0]
        if top.startswith(PROTECTED_PREFIX):
            return '~/' + top
    for root, base in bases['extras']:
        if _inside(folded, base):
            return root
    if PROTECTED_NAME.search(real) and exists(real) and _inside(folded, real_home):
        return posixpath.basename(real)
    return None


# ---------------------------------------------------------------------------------------------------------------------
# The name of a new folder (proposal v0.6, `remote.folder_create`)

# What "trimmed" means: every Unicode separator (categories Zs, Zl, Zp), the tab, the line breaks (U+000A to U+000D) and
# U+0085, so the phone (which writes the same rule out) and the bridge cut the same ends off a name. A zero-width space
# is a format character and stays.
_TRIMMED = '\t\n\x0b\x0c\r\x85'


def _blank(char):
    return char in _TRIMMED or unicodedata.category(char).startswith('Z')


def trim_folder_name(name):
    """The name without the blanks at both ends. `name` is a str."""
    start, end = 0, len(name)
    while start < end and _blank(name[start]):
        start += 1
    while end > start and _blank(name[end - 1]):
        end -= 1
    return name[start:end]


def folder_name_problem(name):
    """Why the (already trimmed) `name` is not a name the bridge takes for a new folder, or None. Proposal v0.6: 1 to 255
    bytes of UTF-8; not `/` or `:`; no control characters; not `.` or `..`; no leading `.` (the listing hides such a
    folder). The answer is one of 'empty', 'encoding', 'long', 'separator', 'control' or 'dot'. A name already present
    in the parent is not a rule of the name: the disk says so."""
    if not name:
        return 'empty'
    try:
        size = len(name.encode('utf-8'))
    except UnicodeEncodeError:  # a lone surrogate: JSON can carry one, UTF-8 cannot
        return 'encoding'
    if size > FOLDER_NAME_BYTES:
        return 'long'
    if '/' in name or ':' in name:
        return 'separator'
    if any(unicodedata.category(char) == 'Cc' for char in name):
        return 'control'
    if name.startswith('.'):  # '.' and '..' too
        return 'dot'
    return None


# ---------------------------------------------------------------------------------------------------------------------
# Addresses (C6: the LAN listener uses private addresses only)

def address_kind(host):
    """'loopback', 'private' (RFC 1918, link-local, IPv6 ULA), 'tailnet' (100.64.0.0/10), 'public', or 'name'."""
    import ipaddress
    try:
        address = ipaddress.ip_address(host.split('%', 1)[0])
    except ValueError:
        return 'name'
    if address.is_loopback:
        return 'loopback'
    if address.version == 4 and address in ipaddress.ip_network('100.64.0.0/10'):
        return 'tailnet'
    if address.is_unspecified:
        return 'public'  # 0.0.0.0 and :: listen on every interface, a public one included
    private = [ipaddress.ip_network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16',
                                                  'fc00::/7', 'fe80::/10')]
    return 'private' if any(address.version == net.version and address in net for net in private) else 'public'


def private_endpoint(host):
    """True for an endpoint a phone may be given: loopback, private or tailnet addresses, `.local` names and MagicDNS
    (`.ts.net`) names."""
    kind = address_kind(host)
    if kind == 'name':
        lower = host.lower().rstrip('.')
        return lower.endswith('.local') or lower.endswith('.ts.net')
    return kind in ('loopback', 'private', 'tailnet')


# ---------------------------------------------------------------------------------------------------------------------
# JPEG

def jpeg_size(data):
    """(width, height) from a JPEG's start-of-frame segment. Raises ValueError for anything that is not a JPEG."""
    if not isinstance(data, (bytes, bytearray)) or data[:3] != b'\xff\xd8\xff':
        raise ValueError('not a JPEG')
    position = 2
    while position + 4 <= len(data):
        if data[position] != 0xff:
            raise ValueError('bad JPEG segment')
        marker = data[position + 1]
        if marker == 0xff:
            position += 1
            continue
        if marker in (0xd8, 0x01) or 0xd0 <= marker <= 0xd7:
            position += 2
            continue
        length = int.from_bytes(data[position + 2:position + 4], 'big')
        if marker in (0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf):
            height = int.from_bytes(data[position + 5:position + 7], 'big')
            width = int.from_bytes(data[position + 7:position + 9], 'big')
            return width, height
        if marker == 0xda:
            break
        position += 2 + length
    raise ValueError('no JPEG frame header')


# ---------------------------------------------------------------------------------------------------------------------
# Pairing link (section 3.2)

LINK_PREFIX = 'pebble-remote://pair?'


def format_endpoint(host, port):
    return ('[' + host + ']' if ':' in host else host) + ':' + str(port)


def parse_endpoint(text):
    """'host:port' or '[ipv6]:port' -> (host, port). Raises ValueError."""
    text = text.strip()
    if text.startswith('['):
        close = text.find(']')
        if close < 0 or text[close + 1:close + 2] != ':':
            raise ValueError('bad endpoint')
        host, port = text[1:close], text[close + 2:]
    else:
        host, sep, port = text.rpartition(':')
        if not sep or ':' in host:
            raise ValueError('bad endpoint')
    if not host or not port.isdigit() or not 0 < int(port) < 65536:
        raise ValueError('bad endpoint')
    return host, int(port)


def build_pairing_link(bid, name, pin, code, endpoints):
    """Every value percent-encoded (RFC 3986 unreserved characters stay as they are)."""
    fields = [('v', '1'), ('bid', bid), ('name', name), ('pin', pin), ('code', code)]
    fields += [('ep', endpoint) for endpoint in endpoints]
    return LINK_PREFIX + '&'.join(key + '=' + quote(value, safe='') for key, value in fields)


def parse_pairing_link(text):
    """Parse a pairing link as the app does (by hand, each value decoded once). Raises ValueError."""
    text = (text or '').strip()
    if not text.lower().startswith(LINK_PREFIX):
        raise ValueError('not a pebble-remote pairing link')
    query = text[len(LINK_PREFIX):].split('#', 1)[0]
    items = []
    for pair in query.split('&'):
        if not pair:
            continue
        key, sep, value = pair.partition('=')
        items.append((unquote(key.replace('+', ' ')), unquote(value.replace('+', ' ')) if sep else ''))

    def first(key):
        return next((value for name, value in items if name == key and value), None)

    endpoints = []
    for name, value in items:
        if name == 'ep':
            try:
                endpoints.append(parse_endpoint(value))
            except ValueError:
                pass
    if first('v') != '1' or not first('bid') or not first('pin') or not first('code') or not endpoints:
        raise ValueError('the pairing link misses v=1, bid, pin, code or an endpoint')
    return {'v': 1, 'bid': first('bid'), 'name': first('name') or 'Mac', 'pin': first('pin'),
            'code': first('code'), 'endpoints': endpoints}


# ---------------------------------------------------------------------------------------------------------------------
# JSON

def now_ms():
    return int(time.time() * 1000)


# ---------------------------------------------------------------------------------------------------------------------
# WebSocket (RFC 6455)

WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
WS_PATH = '/pebble-remote/v1'
WS_SUBPROTOCOL = 'pebble-remote.v1'

OP_CONT, OP_TEXT, OP_BINARY, OP_CLOSE, OP_PING, OP_PONG = 0x0, 0x1, 0x2, 0x8, 0x9, 0xA
_DATA_OPS = (OP_TEXT, OP_BINARY)
_CONTROL_OPS = (OP_CLOSE, OP_PING, OP_PONG)

CLOSE_NORMAL, CLOSE_GOING_AWAY, CLOSE_PROTOCOL, CLOSE_UNSUPPORTED = 1000, 1001, 1002, 1003
CLOSE_NO_STATUS, CLOSE_ABNORMAL, CLOSE_BAD_DATA, CLOSE_POLICY, CLOSE_TOO_BIG = 1005, 1006, 1007, 1008, 1009
CLOSE_INTERNAL, CLOSE_TRY_LATER = 1011, 1013


def ws_accept(key):
    return base64.b64encode(hashlib.sha1((key + WS_GUID).encode('ascii')).digest()).decode('ascii')


def apply_mask(data, mask):
    """XOR data with the 4-byte mask (also unmasks)."""
    length = len(data)
    if not length:
        return b''
    pad = (mask * (length // 4 + 1))[:length]
    return (int.from_bytes(data, 'big') ^ int.from_bytes(pad, 'big')).to_bytes(length, 'big')


def encode_frame(opcode, payload, *, fin=True, mask=None, rsv=0):
    """One frame; masked when mask (4 bytes) is given, as every client-to-server frame must be."""
    payload = bytes(payload)
    first = (0x80 if fin else 0) | (rsv << 4) | opcode
    flag = 0x80 if mask else 0
    size = len(payload)
    if size < 126:
        head = bytes([first, flag | size])
    elif size < 1 << 16:
        head = bytes([first, flag | 126]) + size.to_bytes(2, 'big')
    else:
        head = bytes([first, flag | 127]) + size.to_bytes(8, 'big')
    if mask:
        return head + mask + apply_mask(payload, mask)
    return head + payload


def valid_close_code(code):
    return code in (1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014) or 3000 <= code <= 4999


class WebSocketError(Exception):
    def __init__(self, code, reason):
        super().__init__(reason)
        self.code, self.reason = code, reason


class WebSocket:
    """A WebSocket connection over asyncio streams, after the opening handshake.

    recv() returns a text message as str, a binary one as bytes, or None once the connection is closed (then
    close_code and close_reason say why: the peer's close frame, 1006 for a dropped connection, or our own close code
    after a protocol error). Pings are answered with pongs inside recv(), so something must keep calling recv()."""

    def __init__(self, reader, writer, *, client, max_message=1 << 20):
        self.reader, self.writer, self.client = reader, writer, client
        self.max_message = max_message
        self.close_sent = False
        self.closed = False
        self.close_code = None
        self.close_reason = ''
        self.last_received = time.monotonic()
        self._lock = asyncio.Lock()
        self._pings = {}
        self._done = asyncio.Event()

    # -- sending ------------------------------------------------------------------------------------------------------

    async def send_frame(self, opcode, payload, *, fin=True, rsv=0):
        if self.closed or (self.close_sent and opcode != OP_CLOSE):
            raise ConnectionError('the WebSocket is closing')
        frame = encode_frame(opcode, payload, fin=fin, mask=os.urandom(4) if self.client else None, rsv=rsv)
        async with self._lock:
            self.writer.write(frame)
            await self.writer.drain()

    async def send_text(self, text):
        await self.send_frame(OP_TEXT, text.encode('utf-8'))

    async def send_binary(self, data):
        await self.send_frame(OP_BINARY, data)

    async def ping(self, payload=b'', timeout=10.0):
        """Round trip in seconds, from a ping to its pong (needs a recv() loop running)."""
        payload = bytes(payload) or os.urandom(8)
        waiter = asyncio.get_running_loop().create_future()
        self._pings[payload] = waiter
        started = time.monotonic()
        try:
            await self.send_frame(OP_PING, payload)
            await asyncio.wait_for(waiter, timeout)
        finally:
            self._pings.pop(payload, None)
        return time.monotonic() - started

    async def close(self, code=CLOSE_NORMAL, reason='', timeout=2.0):
        """Start the closing handshake, then wait (a recv() loop must be running) for the peer's close or drop it."""
        await self._send_close(code, reason)
        if self.closed:
            return
        try:
            await asyncio.wait_for(self._done.wait(), timeout)
        except (asyncio.TimeoutError, TimeoutError):
            self.abort()

    async def _send_close(self, code, reason):
        if self.close_sent or self.closed:
            return
        self.close_sent = True
        payload = b'' if code is None else code.to_bytes(2, 'big') + reason.encode('utf-8')[:123]
        if self.close_code is None and code is not None:
            self.close_code, self.close_reason = code, reason
        try:
            await self.send_frame(OP_CLOSE, payload)
        except (ConnectionError, OSError, RuntimeError):
            self._finish()

    def abort(self):
        try:
            self.writer.transport.abort()
        except Exception:
            pass
        self._finish(CLOSE_ABNORMAL)

    def _finish(self, code=None):
        if self.close_code is None:
            self.close_code = code if code is not None else CLOSE_ABNORMAL
        if not self.closed:
            self.closed = True
            try:
                self.writer.close()
            except Exception:
                pass
        self._done.set()
        for waiter in self._pings.values():
            if not waiter.done():
                waiter.set_exception(ConnectionError('closed'))

    async def wait_closed(self):
        await self._done.wait()

    # -- receiving ----------------------------------------------------------------------------------------------------

    async def _read_frame(self):
        head = await self.reader.readexactly(2)
        fin, rsv, opcode = head[0] & 0x80, head[0] & 0x70, head[0] & 0x0f
        masked, size = head[1] & 0x80, head[1] & 0x7f
        if rsv:
            raise WebSocketError(CLOSE_PROTOCOL, 'reserved bits set (no extensions were agreed)')
        if opcode not in _DATA_OPS + _CONTROL_OPS + (OP_CONT,):
            raise WebSocketError(CLOSE_PROTOCOL, 'unknown opcode')
        if size == 126:
            size = int.from_bytes(await self.reader.readexactly(2), 'big')
            if size < 126:
                raise WebSocketError(CLOSE_PROTOCOL, 'non-minimal frame length')
        elif size == 127:
            size = int.from_bytes(await self.reader.readexactly(8), 'big')
            if size < 1 << 16 or size >> 63:
                raise WebSocketError(CLOSE_PROTOCOL, 'bad frame length')
        if self.client and masked:
            raise WebSocketError(CLOSE_PROTOCOL, 'server frames must not be masked')
        if not self.client and not masked:
            raise WebSocketError(CLOSE_PROTOCOL, 'client frames must be masked')
        if opcode in _CONTROL_OPS and (not fin or size > 125):
            raise WebSocketError(CLOSE_PROTOCOL, 'bad control frame')
        if size > self.max_message:
            raise WebSocketError(CLOSE_TOO_BIG, 'message too big')
        mask = await self.reader.readexactly(4) if masked else None
        payload = await self.reader.readexactly(size)
        self.last_received = time.monotonic()
        return bool(fin), opcode, apply_mask(payload, mask) if mask else payload

    async def recv(self):
        if self.closed:
            return None
        parts, kind, size = None, None, 0
        try:
            while True:
                fin, opcode, payload = await self._read_frame()
                if opcode == OP_PING:
                    if not self.close_sent:
                        await self.send_frame(OP_PONG, payload)
                    continue
                if opcode == OP_PONG:
                    waiter = self._pings.get(payload)
                    if waiter is not None and not waiter.done():
                        waiter.set_result(True)
                    continue
                if opcode == OP_CLOSE:
                    return await self._on_close(payload)
                if opcode == OP_CONT:
                    if parts is None:
                        raise WebSocketError(CLOSE_PROTOCOL, 'continuation without a message')
                    parts.append(payload)
                else:
                    if parts is not None:
                        raise WebSocketError(CLOSE_PROTOCOL, 'new message before the last one finished')
                    parts, kind, size = [payload], opcode, 0
                size += len(payload)
                if size > self.max_message:
                    raise WebSocketError(CLOSE_TOO_BIG, 'message too big')
                if not fin:
                    continue
                data = b''.join(parts)
                parts = None
                if kind == OP_TEXT:
                    try:
                        return data.decode('utf-8')
                    except UnicodeDecodeError:
                        raise WebSocketError(CLOSE_BAD_DATA, 'text message is not UTF-8') from None
                return data
        except WebSocketError as exc:
            if self.close_code is None:
                self.close_code, self.close_reason = exc.code, exc.reason
            await self._send_close(exc.code, exc.reason)
            self._finish()
            return None
        except (asyncio.IncompleteReadError, ConnectionError, OSError):
            self._finish(CLOSE_ABNORMAL)
            return None

    async def _on_close(self, payload):
        code, reason = CLOSE_NO_STATUS, ''
        reply = CLOSE_NORMAL
        if len(payload) == 1:
            code, reply = CLOSE_PROTOCOL, CLOSE_PROTOCOL
        elif len(payload) >= 2:
            code = int.from_bytes(payload[:2], 'big')
            try:
                reason = payload[2:].decode('utf-8')
            except UnicodeDecodeError:
                reply = CLOSE_BAD_DATA
            if not valid_close_code(code):
                reply = CLOSE_PROTOCOL
            elif reply == CLOSE_NORMAL:
                reply = code
        if self.close_code is None or not self.close_sent:
            self.close_code, self.close_reason = code, reason
        await self._send_close(reply, '')
        self._finish()
        return None


async def _read_http_head(reader, timeout):
    head = await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'), timeout)
    if len(head) > 16384:
        raise ValueError('header too long')
    lines = head.decode('latin-1').split('\r\n')
    headers = {}
    for line in lines[1:]:
        if line:
            name, sep, value = line.partition(':')
            if not sep:
                raise ValueError('bad header line')
            headers.setdefault(name.strip().lower(), []).append(value.strip())
    return lines[0], headers


def _tokens(headers, name):
    return [token.strip() for value in headers.get(name, []) for token in value.split(',') if token.strip()]


async def server_handshake(reader, writer, *, path=WS_PATH, subprotocol=WS_SUBPROTOCOL, timeout=10.0,
                           max_message=1 << 20):
    """Read the HTTP upgrade request and answer it. Returns a server-role WebSocket, or None after refusing."""

    async def refuse(status, extra=''):
        writer.write(('HTTP/1.1 ' + status + '\r\nContent-Length: 0\r\nConnection: close\r\n' + extra + '\r\n')
                     .encode('latin-1'))
        try:
            await writer.drain()
        finally:
            writer.close()
        return None

    try:
        request_line, headers = await _read_http_head(reader, timeout)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError, TimeoutError, ValueError,
            ConnectionError, OSError):
        try:
            writer.close()
        except Exception:
            pass
        return None
    parts = request_line.split(' ')
    if len(parts) != 3 or parts[0] != 'GET' or not parts[2].startswith('HTTP/1.1'):
        return await refuse('400 Bad Request')
    if parts[1] != path:
        return await refuse('404 Not Found')
    if 'websocket' not in [t.lower() for t in _tokens(headers, 'upgrade')] or \
            'upgrade' not in [t.lower() for t in _tokens(headers, 'connection')]:
        return await refuse('400 Bad Request')
    if _tokens(headers, 'sec-websocket-version') != ['13']:
        return await refuse('426 Upgrade Required', 'Sec-WebSocket-Version: 13\r\n')
    keys = headers.get('sec-websocket-key', [])
    try:
        if len(keys) != 1 or len(base64.b64decode(keys[0], validate=True)) != 16:
            raise ValueError
    except ValueError:
        return await refuse('400 Bad Request')
    if subprotocol not in _tokens(headers, 'sec-websocket-protocol'):
        return await refuse('400 Bad Request')
    writer.write(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                  'Sec-WebSocket-Accept: ' + ws_accept(keys[0]) + '\r\n'
                  'Sec-WebSocket-Protocol: ' + subprotocol + '\r\n\r\n').encode('latin-1'))
    await writer.drain()
    return WebSocket(reader, writer, client=False, max_message=max_message)


class HandshakeRefused(Exception):
    def __init__(self, status, headers):
        super().__init__('the server answered ' + status)
        self.status, self.headers = status, headers


async def client_handshake(reader, writer, host_header, *, path=WS_PATH, subprotocol=WS_SUBPROTOCOL, timeout=10.0,
                           max_message=16 << 20):
    """Send the upgrade request and check the answer. Returns (client-role WebSocket, response headers)."""
    key = base64.b64encode(os.urandom(16)).decode('ascii')
    request = ('GET ' + path + ' HTTP/1.1\r\nHost: ' + host_header + '\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
               'Sec-WebSocket-Key: ' + key + '\r\nSec-WebSocket-Version: 13\r\n'
               + ('Sec-WebSocket-Protocol: ' + subprotocol + '\r\n' if subprotocol else '') + '\r\n')
    writer.write(request.encode('latin-1'))
    await writer.drain()
    status_line, headers = await _read_http_head(reader, timeout)
    parts = status_line.split(' ', 2)
    if len(parts) < 2 or parts[1] != '101':
        raise HandshakeRefused(status_line, headers)
    if headers.get('sec-websocket-accept', [None])[0] != ws_accept(key):
        raise HandshakeRefused('101 with a wrong Sec-WebSocket-Accept', headers)
    if 'websocket' not in [t.lower() for t in _tokens(headers, 'upgrade')]:
        raise HandshakeRefused('101 without Upgrade: websocket', headers)
    return WebSocket(reader, writer, client=True, max_message=max_message), headers
