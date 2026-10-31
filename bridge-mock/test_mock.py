"""Tests for the mock bridge, its wire helpers and the conformance checker.

    python3 -I -B -m unittest discover -s bridge-mock -p 'test_*.py'   (from the repository root)
    python3 -I bridge-mock/test_mock.py

Unit tests: ECDSA P-256 (RFC 6979 vectors, openssl in both directions, bad and malformed signatures), the SPKI pin,
WebSocket framing (RFC 6455's own examples, fragmentation, control frames, protocol errors), the pairing link, the
signed transcripts, token batching and the resume buffer, and the simulated Pebble's card flow. Proposal v0.5: the
folder rules (`remote.folders`, what `set_workspace` and `new_chat` may connect), the nine methods that open things on
the Mac, `terminal_propose` and `attach_url`. Proposal v0.6: the name rules and `remote.folder_create` (a real folder in a
test tree), and the ten minutes in which a folder a device made connects with the unlock alone. End to end: the mock on an ephemeral 127.0.0.1 port, and conformance.py
against it; every check must pass, and the v0.5 and v0.6 rows must fail a bridge that breaks the rules. Standard
library only.
"""

import asyncio
import contextlib
import io
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from collections import deque
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # no __pycache__ in the repository
sys.path.insert(0, HERE)
import remote_wire as wire  # noqa: E402
import mock_bridge  # noqa: E402

OPENSSL = '/usr/bin/openssl' if os.access('/usr/bin/openssl', os.X_OK) else shutil.which('openssl')
mock_bridge.QUIET = True


def openssl(*args, data=None, cwd=None):
    return subprocess.run([OPENSSL, *args], input=data, capture_output=True, cwd=cwd, timeout=30)


# =====================================================================================================================
# ECDSA P-256
# =====================================================================================================================

RFC_X = 0xC9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721
RFC_UX = 0x60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6
RFC_UY = 0x7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299


class ECDSATests(unittest.TestCase):
    def test_rfc6979_public_key(self):
        self.assertEqual(wire.point_mul(RFC_X, wire.G), (RFC_UX, RFC_UY))

    def test_rfc6979_sample_and_test_vectors(self):
        # RFC 6979 appendix A.2.5, ECDSA P-256 with SHA-256
        vectors = [
            (b'sample', 0xA6E3C57DD01ABE90086538398355DD4C3B17AA873382B0F24D6129493D8AAD60,
             0xEFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716,
             0xF7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8),
            (b'test', 0xD16B6AE827F17175E040871A1C7EC3500192C4C92677336EC2537ACAEE0008E0,
             0xF1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367,
             0x019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083),
        ]
        for message, k, r, s in vectors:
            self.assertEqual(next(wire.rfc6979_nonces(RFC_X, wire.sha256(message))), k)
            self.assertEqual(wire.sign_rs(RFC_X, message), (r, s))
            self.assertTrue(wire.verify((RFC_UX, RFC_UY), message, wire.der_encode_signature(r, s)))

    def test_sign_verify_round_trip(self):
        for _ in range(3):
            key = wire.SigningKey()
            message = os.urandom(40)
            signature = key.sign(message)
            self.assertTrue(wire.verify(key.public, message, signature))
            self.assertEqual(signature, key.sign(message))  # deterministic

    def test_high_s_is_accepted(self):
        r, s = wire.sign_rs(RFC_X, b'sample')
        self.assertTrue(wire.verify((RFC_UX, RFC_UY), b'sample', wire.der_encode_signature(r, wire.N - s)))

    def test_known_bad_signatures(self):
        key = wire.SigningKey()
        message = b'pebble-remote/v1/hello\nbid\n'
        r, s = wire.sign_rs(key.private, message)
        other = wire.SigningKey()
        bad = {
            'another message': (key.public, b'pebble-remote/v1/hello\nbid!\n', wire.der_encode_signature(r, s)),
            'another key': (other.public, message, wire.der_encode_signature(r, s)),
            'r changed': (key.public, message, wire.der_encode_signature(r ^ 1, s)),
            's changed': (key.public, message, wire.der_encode_signature(r, s ^ 1)),
            'r zero': (key.public, message, wire.der_encode_signature(0, s)),
            's zero': (key.public, message, wire.der_encode_signature(r, 0)),
            'r = n': (key.public, message, wire.der_encode_signature(wire.N, s)),
            's = n': (key.public, message, wire.der_encode_signature(r, wire.N)),
            'r and s swapped': (key.public, message, wire.der_encode_signature(s, r)),
            'empty': (key.public, message, b''),
            'not DER': (key.public, message, os.urandom(70)),
        }
        for label, (public, signed, signature) in bad.items():
            with self.subTest(label):
                self.assertFalse(wire.verify(public, signed, signature))

    def test_malformed_der_is_refused(self):
        good = wire.sign(RFC_X, b'sample')
        self.assertEqual(wire.der_decode_signature(good), wire.sign_rs(RFC_X, b'sample'))
        r_bytes = good[4:4 + good[3]]
        malformed = {
            'trailing byte': good + b'\x00',
            'sequence length too long': bytes([0x30, good[1] + 1]) + good[2:] + b'\x00',
            'not a sequence': b'\x31' + good[1:],
            'long-form length for a short value': b'\x30\x81' + good[1:],
            'negative r': b'\x30\x08\x02\x01\x81\x02\x03\x01\x00\x01',
            'r with a needless leading zero': b'\x30\x09\x02\x02\x00\x01\x02\x03\x01\x00\x01',
            'zero-length r': b'\x30\x07\x02\x00\x02\x03\x01\x00\x01',
            'truncated': good[:-1],
            'r is an OCTET STRING': good[:2] + b'\x04' + good[3:],
        }
        self.assertTrue(r_bytes)
        for label, signature in malformed.items():
            with self.subTest(label):
                with self.assertRaises(ValueError):
                    wire.der_decode_signature(signature)
                self.assertFalse(wire.verify((RFC_UX, RFC_UY), b'sample', signature))

    def test_points_are_validated(self):
        point = wire.encode_point((RFC_UX, RFC_UY))
        self.assertEqual(wire.decode_point(point), (RFC_UX, RFC_UY))
        bad = {
            'compressed prefix': b'\x02' + point[1:33],
            'wrong prefix': b'\x05' + point[1:],
            'short': point[:-1],
            'off the curve': point[:-1] + bytes([point[-1] ^ 1]),
            'x = p': b'\x04' + wire.P.to_bytes(32, 'big') + point[33:],
            'infinity-ish zeros': b'\x04' + bytes(64),
        }
        for label, data in bad.items():
            with self.subTest(label):
                with self.assertRaises(ValueError):
                    wire.decode_point(data)
        self.assertFalse(wire.verify((RFC_UX, RFC_UY + 1), b'sample', wire.sign(RFC_X, b'sample')))

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_openssl_interop_both_ways(self):
        with tempfile.TemporaryDirectory() as folder:
            key = os.path.join(folder, 'key.pem')
            self.assertEqual(openssl('ecparam', '-name', 'prime256v1', '-param_enc', 'named_curve', '-genkey',
                                     '-noout', '-out', key).returncode, 0)
            der = openssl('ec', '-in', key, '-outform', 'DER').stdout
            spki = openssl('ec', '-in', key, '-pubout', '-outform', 'DER').stdout
            private = wire.sec1_private_scalar(der)
            self.assertTrue(spki.startswith(wire.SPKI_P256_PREFIX))
            public = wire.decode_point(spki[len(wire.SPKI_P256_PREFIX):])
            self.assertEqual(wire.point_mul(private, wire.G), public)
            message = b'pebble-remote/v1/proof\nb-bid\nd-device\ne-epoch\nr42\napprove\nhash\n1730000000000\n'
            path = os.path.join(folder, 'message')
            with open(path, 'wb') as handle:
                handle.write(message)
            # openssl signs, we verify (and refuse it for a changed message or a flipped bit)
            signature = openssl('dgst', '-sha256', '-sign', key, path).stdout
            self.assertTrue(wire.verify(public, message, signature))
            self.assertFalse(wire.verify(public, message + b'x', signature))
            flipped = bytearray(signature)
            flipped[-1] ^= 1
            self.assertFalse(wire.verify(public, message, bytes(flipped)))
            # we sign, openssl verifies (and refuses a tampered signature)
            public_pem = os.path.join(folder, 'public.pem')
            with open(public_pem, 'w') as handle:
                handle.write(wire.public_key_pem(public))
            for signature, expected in ((wire.sign(private, message), 0), (bytes(flipped), 1)):
                signature_path = os.path.join(folder, 'signature.der')
                with open(signature_path, 'wb') as handle:
                    handle.write(signature)
                done = openssl('dgst', '-sha256', '-verify', public_pem, '-signature', signature_path, path)
                self.assertEqual(done.returncode, expected, done.stdout + done.stderr)


# =====================================================================================================================
# The pin
# =====================================================================================================================

@unittest.skipUnless(OPENSSL, 'openssl is not installed')
class PinTests(unittest.TestCase):
    def test_pin_matches_openssl_and_the_fixed_prefix(self):
        with tempfile.TemporaryDirectory() as folder:
            identity = mock_bridge.Identity(os.path.join(folder, 'state'), OPENSSL)
            cert_der = identity.cert_der
            spki = wire.spki_from_certificate(cert_der)
            self.assertEqual(len(spki), 91)
            self.assertTrue(spki.startswith(wire.SPKI_P256_PREFIX))
            public = openssl('x509', '-in', identity.cert_path, '-pubkey', '-noout').stdout
            spki_openssl = openssl('pkey', '-pubin', '-outform', 'DER', data=public).stdout
            self.assertEqual(spki, spki_openssl)
            self.assertEqual(identity.pin, wire.b64u(wire.sha256(spki_openssl)))
            self.assertEqual(len(identity.pin), 43)
            self.assertNotIn('=', identity.pin)
            # files are the person's alone
            self.assertEqual(stat.S_IMODE(os.stat(identity.dir).st_mode), 0o700)
            for path in (identity.key_path, identity.cert_path, os.path.join(identity.dir, 'bridge.json')):
                self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600, path)

    def test_certificate_is_reissued_with_the_same_key(self):
        with tempfile.TemporaryDirectory() as folder:
            state = os.path.join(folder, 'state')
            first = mock_bridge.Identity(state, OPENSSL)
            os.remove(first.cert_path)
            second = mock_bridge.Identity(state, OPENSSL)
            self.assertEqual(first.pin, second.pin)
            self.assertEqual(first.bid, second.bid)
            self.assertNotEqual(first.cert_der, second.cert_der)


# =====================================================================================================================
# WebSocket framing
# =====================================================================================================================

class FakeTransport:
    aborted = False

    def abort(self):
        self.aborted = True


class FakeWriter:
    def __init__(self):
        self.data = bytearray()
        self.closed = False
        self.transport = FakeTransport()

    def write(self, data):
        self.data += data

    async def drain(self):
        pass

    def close(self):
        self.closed = True


def parse_frames(data):
    """Unmasked frames, as the server sends them: [(fin, opcode, payload)]."""
    frames, position = [], 0
    while position < len(data):
        first, second = data[position], data[position + 1]
        size, position = second & 0x7f, position + 2
        if size == 126:
            size, position = int.from_bytes(data[position:position + 2], 'big'), position + 2
        elif size == 127:
            size, position = int.from_bytes(data[position:position + 8], 'big'), position + 8
        frames.append((bool(first & 0x80), first & 0x0f, bytes(data[position:position + size])))
        position += size
    return frames


class WebSocketTests(unittest.IsolatedAsyncioTestCase):
    def socket(self, data, client=False, max_message=1 << 20):
        reader = asyncio.StreamReader()
        reader.feed_data(bytes(data))
        reader.feed_eof()
        writer = FakeWriter()
        return wire.WebSocket(reader, writer, client=client, max_message=max_message), writer

    def test_accept_key_rfc_example(self):
        self.assertEqual(wire.ws_accept('dGhlIHNhbXBsZSBub25jZQ=='), 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=')

    def test_rfc_masked_hello(self):
        frame = wire.encode_frame(wire.OP_TEXT, b'Hello', mask=bytes.fromhex('37fa213d'))
        self.assertEqual(frame, bytes.fromhex('818537fa213d7f9f4d5158'))
        self.assertEqual(wire.apply_mask(wire.apply_mask(b'Hello', b'abcd'), b'abcd'), b'Hello')

    async def test_server_reads_rfc_masked_hello(self):
        ws, _ = self.socket(bytes.fromhex('818537fa213d7f9f4d5158'))
        self.assertEqual(await ws.recv(), 'Hello')

    async def test_client_reads_rfc_unmasked_and_fragmented_hello(self):
        ws, _ = self.socket(bytes.fromhex('810548656c6c6f') + bytes.fromhex('010348656c') + bytes.fromhex('80026c6f'),
                            client=True)
        self.assertEqual(await ws.recv(), 'Hello')
        self.assertEqual(await ws.recv(), 'Hello')

    async def test_lengths_round_trip(self):
        for size in (0, 1, 125, 126, 127, 65535, 65536, 140000):
            with self.subTest(size=size):
                payload = os.urandom(size)
                ws, _ = self.socket(wire.encode_frame(wire.OP_BINARY, payload, mask=os.urandom(4)))
                self.assertEqual(await ws.recv(), payload)

    async def test_fragments_with_a_ping_between(self):
        mask = os.urandom(4)
        data = (wire.encode_frame(wire.OP_TEXT, '{"t":'.encode(), fin=False, mask=mask)
                + wire.encode_frame(wire.OP_PING, b'ping!', mask=mask)
                + wire.encode_frame(wire.OP_CONT, '"req",'.encode(), fin=False, mask=mask)
                + wire.encode_frame(wire.OP_CONT, '"x":"é"}'.encode(), fin=True, mask=mask))
        ws, writer = self.socket(data)
        self.assertEqual(await ws.recv(), '{"t":"req","x":"é"}')
        self.assertEqual(parse_frames(writer.data), [(True, wire.OP_PONG, b'ping!')])

    async def test_a_split_utf8_character_across_fragments(self):
        text = 'Pebble ✓'.encode()
        mask = os.urandom(4)
        data = (wire.encode_frame(wire.OP_TEXT, text[:-2], fin=False, mask=mask)
                + wire.encode_frame(wire.OP_CONT, text[-2:], mask=mask))
        ws, _ = self.socket(data)
        self.assertEqual(await ws.recv(), 'Pebble ✓')

    async def test_protocol_errors_close_with_the_right_code(self):
        mask = os.urandom(4)
        cases = {
            'unmasked client frame': (wire.encode_frame(wire.OP_TEXT, b'hi'), wire.CLOSE_PROTOCOL),
            'continuation without a start': (wire.encode_frame(wire.OP_CONT, b'hi', mask=mask), wire.CLOSE_PROTOCOL),
            'control frame over 125 bytes': (wire.encode_frame(wire.OP_PING, bytes(126), mask=mask),
                                             wire.CLOSE_PROTOCOL),
            'fragmented control frame': (wire.encode_frame(wire.OP_PING, b'x', fin=False, mask=mask),
                                         wire.CLOSE_PROTOCOL),
            'reserved bits': (wire.encode_frame(wire.OP_TEXT, b'hi', mask=mask, rsv=4), wire.CLOSE_PROTOCOL),
            'unknown opcode': (wire.encode_frame(0x3, b'hi', mask=mask), wire.CLOSE_PROTOCOL),
            'invalid UTF-8': (wire.encode_frame(wire.OP_TEXT, b'\xff\xfe', mask=mask), wire.CLOSE_BAD_DATA),
            'non-minimal length': (bytes([0x81, 0x80 | 126, 0, 5]) + mask + wire.apply_mask(b'hello', mask),
                                   wire.CLOSE_PROTOCOL),
            'new message inside a fragmented one': (
                wire.encode_frame(wire.OP_TEXT, b'a', fin=False, mask=mask)
                + wire.encode_frame(wire.OP_TEXT, b'b', mask=mask), wire.CLOSE_PROTOCOL),
            'message too big': (wire.encode_frame(wire.OP_TEXT, bytes(2000), mask=mask), wire.CLOSE_TOO_BIG),
        }
        for label, (data, code) in cases.items():
            with self.subTest(label):
                ws, writer = self.socket(data, max_message=1000)
                self.assertIsNone(await ws.recv())
                self.assertEqual(ws.close_code, code)
                sent = parse_frames(writer.data)
                self.assertEqual(sent[-1][1], wire.OP_CLOSE)
                self.assertEqual(int.from_bytes(sent[-1][2][:2], 'big'), code)

    async def test_server_frames_must_not_be_masked(self):
        ws, _ = self.socket(wire.encode_frame(wire.OP_TEXT, b'hi', mask=os.urandom(4)), client=True)
        self.assertIsNone(await ws.recv())
        self.assertEqual(ws.close_code, wire.CLOSE_PROTOCOL)

    async def test_close_handshake_echoes_the_code(self):
        ws, writer = self.socket(wire.encode_frame(wire.OP_CLOSE, (1000).to_bytes(2, 'big') + b'bye',
                                                   mask=os.urandom(4)))
        self.assertIsNone(await ws.recv())
        self.assertEqual((ws.close_code, ws.close_reason), (1000, 'bye'))
        self.assertEqual(parse_frames(writer.data), [(True, wire.OP_CLOSE, (1000).to_bytes(2, 'big'))])
        self.assertTrue(writer.closed)

    async def test_close_with_an_invalid_code_is_answered_1002(self):
        ws, writer = self.socket(wire.encode_frame(wire.OP_CLOSE, (1005).to_bytes(2, 'big'), mask=os.urandom(4)))
        self.assertIsNone(await ws.recv())
        self.assertEqual(parse_frames(writer.data)[-1][2][:2], (1002).to_bytes(2, 'big'))

    async def test_dropped_connection_is_1006(self):
        ws, _ = self.socket(b'\x81')
        self.assertIsNone(await ws.recv())
        self.assertEqual(ws.close_code, wire.CLOSE_ABNORMAL)

    async def test_server_handshake_checks_the_upgrade(self):
        key = 'dGhlIHNhbXBsZSBub25jZQ=='
        good = ('GET /pebble-remote/v1 HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\n'
                'Sec-WebSocket-Key: ' + key + '\r\nSec-WebSocket-Version: 13\r\n'
                'Sec-WebSocket-Protocol: chat, pebble-remote.v1\r\n\r\n')
        cases = {
            'good': (good, '101'),
            'wrong path': (good.replace('/pebble-remote/v1', '/other'), '404'),
            'no subprotocol': (good.replace('Sec-WebSocket-Protocol: chat, pebble-remote.v1\r\n', ''), '400'),
            'old version': (good.replace('Version: 13', 'Version: 8'), '426'),
            'bad key': (good.replace(key, 'short'), '400'),
            'not an upgrade': (good.replace('Upgrade: websocket\r\n', ''), '400'),
            'POST': (good.replace('GET', 'POST', 1), '400'),
        }
        for label, (request, status) in cases.items():
            with self.subTest(label):
                reader = asyncio.StreamReader()
                reader.feed_data(request.encode())
                reader.feed_eof()
                writer = FakeWriter()
                ws = await wire.server_handshake(reader, writer)
                answer = writer.data.decode()
                self.assertTrue(answer.startswith('HTTP/1.1 ' + status), answer)
                self.assertEqual(ws is not None, status == '101')
                if status == '101':
                    self.assertIn('Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n', answer)
                    self.assertIn('Sec-WebSocket-Protocol: pebble-remote.v1\r\n', answer)


# =====================================================================================================================
# The pairing link and the transcripts
# =====================================================================================================================

class LinkAndTranscriptTests(unittest.TestCase):
    def test_link_round_trip_with_ipv6_and_spaces(self):
        link = wire.build_pairing_link('b-1', 'Sam’s MacBook Air', 'PIN_pin-0', 'code_-1',
                                       ['192.168.1.20:47800', wire.format_endpoint('fe80::1', 47800),
                                        'mac.local:47800'])
        self.assertIn('name=Sam%E2%80%99s%20MacBook%20Air', link)
        self.assertIn('ep=%5Bfe80%3A%3A1%5D%3A47800', link)
        self.assertNotIn('+', link)
        parsed = wire.parse_pairing_link(link)
        self.assertEqual(parsed['name'], 'Sam’s MacBook Air')
        self.assertEqual(parsed['endpoints'], [('192.168.1.20', 47800), ('fe80::1', 47800), ('mac.local', 47800)])
        self.assertEqual((parsed['bid'], parsed['pin'], parsed['code']), ('b-1', 'PIN_pin-0', 'code_-1'))

    def test_link_needs_its_fields(self):
        for link in ('pebble-remote://pair?v=1&bid=b&pin=p&ep=h%3A1', 'pebble-remote://pair?v=2&bid=b&pin=p&code=c&ep=h%3A1',
                     'https://example.com/?v=1', 'pebble-remote://pair?v=1&bid=b&pin=p&code=c&ep=nohost'):
            with self.subTest(link):
                with self.assertRaises(ValueError):
                    wire.parse_pairing_link(link)

    def test_transcripts_are_exact(self):
        self.assertEqual(wire.t_pair('b', 'n', 'p', 'c', 'dk', 'ak'), b'pebble-remote/v1/pair\nb\nn\np\nc\ndk\nak\n')
        self.assertEqual(wire.t_hello('b', 'd', 'n', 'p'), b'pebble-remote/v1/hello\nb\nd\nn\np\n')
        params = '{"id":"c1","action_id":"a9"}'
        digest = wire.b64u(wire.sha256(params.encode()))
        self.assertEqual(wire.t_proof_v02('b', 'd', 'e', 'r42', 'approve', params, 1730000000000),
                         ('pebble-remote/v1/proof\nb\nd\ne\nr42\napprove\n' + digest + '\n1730000000000\n').encode())
        with self.assertRaises(ValueError):
            wire.t_hello('b', 'd\nforged', 'n', 'p')
        with self.assertRaises(ValueError):
            wire.t_proof('b', 'd', 'e', 'n', 'r', 'i', 'm', '{}', 1.5)

    def test_t_proof_v03_golden_agreed_with_lane_b(self):
        # docs/TEAM_BOARD.md 01:16 (lane C), reproduced by lane B's client at 01:22
        params = '{"action_id":"a9","id":"c1"}'
        transcript = wire.t_proof('b-1', 'd-1', 'e-1', 'n-1', 'r42', '0f8fad5b-d9cb-469f-a165-70867728950e',
                                  'approve', params, 1761780000000)
        self.assertEqual(wire.b64u(wire.sha256(params.encode())), 'IjGkhgxEHL96SaH_YpvZ_QIRTIdaiepSsS2nStVZGXM')
        self.assertEqual(transcript, b'pebble-remote/v1/proof\nb-1\nd-1\ne-1\nn-1\nr42\n'
                                     b'0f8fad5b-d9cb-469f-a165-70867728950e\napprove\n'
                                     b'IjGkhgxEHL96SaH_YpvZ_QIRTIdaiepSsS2nStVZGXM\n1761780000000\n')
        self.assertEqual(wire.sha256(transcript).hex(),
                         'd0e32872b7515632da3ffaa1059db00ad0ba78c80297ed5c495492479d70a19e')

    def test_the_confirmation_code_formula_and_its_vectors(self):
        """X-1: the first 4 bytes of SHA-256 over "pebble-remote/v1/sas\n" + T_pair, as a big-endian unsigned integer, mod
        1,000,000, zero-padded to 6 digits. The vectors are the ones the phone's lane tests against."""
        import hashlib
        self.assertEqual(wire.SAS_LABEL, b'pebble-remote/v1/sas\n')
        first = wire.SAS_VECTORS[0]
        t_pair = wire.t_pair(*first['fields'])
        self.assertEqual(t_pair, b'pebble-remote/v1/pair\nb-1\nn-1\np-1\nc-1\ndk-1\nak-1\n')
        for vector in wire.SAS_VECTORS:
            transcript = wire.t_pair(*vector['fields'])
            digest = hashlib.sha256(b'pebble-remote/v1/sas\n' + transcript).digest()  # written out, not wire.sas_code
            self.assertEqual(digest.hex(), vector['digest'])
            self.assertEqual('%06d' % (int.from_bytes(digest[:4], 'big') % 1000000), vector['code'])
            self.assertEqual(wire.sas_code(transcript), vector['code'])
        self.assertEqual(wire.sas_code(t_pair), '035072')   # the integer is 1460035072: the zero is kept
        self.assertEqual(wire.sas_code(wire.t_pair(*wire.SAS_VECTORS[1]['fields'])), '994460')
        self.assertEqual(int.from_bytes(bytes.fromhex(first['digest'])[:4], 'big'), 1460035072)
        # any field changes the code, and only T_pair (what both signatures cover) goes into it
        for index in range(6):
            fields = list(first['fields'])
            fields[index] += 'x'
            self.assertNotEqual(wire.sas_code(wire.t_pair(*fields)), '035072', index)
        with self.assertRaises(ValueError):
            wire.sas_code('not bytes')
        self.assertEqual(wire.PAIR_CONFIRM_SECONDS, 120)

    def test_request_id_charset(self):
        for good in ('r1', 'A-z_0-9', 'x' * 64, '0f8fad5b-d9cb-469f-a165-70867728950e'):
            self.assertTrue(wire.valid_id(good), good)
        for bad in ('', 'x' * 65, 'has space', 'dot.ted', 'line\nbreak', 'é', None, 42):
            self.assertFalse(wire.valid_id(bad), repr(bad))

    def test_private_addresses(self):
        cases = {'127.0.0.1': 'loopback', '::1': 'loopback', '192.168.1.20': 'private', '10.0.0.5': 'private',
                 '172.20.1.1': 'private', '169.254.3.4': 'private', 'fe80::1': 'private', 'fd12::1': 'private',
                 '100.101.102.103': 'tailnet', '8.8.8.8': 'public', '172.32.0.1': 'public', '0.0.0.0': 'public',
                 '::': 'public', 'mac.local': 'name'}
        for host, kind in cases.items():
            self.assertEqual(wire.address_kind(host), kind, host)
        for host, private in (('mac.local', True), ('mac.tail1234.ts.net', True), ('example.com', False),
                              ('100.64.0.1', True), ('8.8.8.8', False), ('192.168.0.1', True)):
            self.assertEqual(wire.private_endpoint(host), private, host)

    def test_base64url_is_strict(self):
        self.assertEqual(wire.b64u(b'\xfb\xff'), '-_8')
        self.assertEqual(wire.b64u_decode('-_8'), b'\xfb\xff')
        for bad in ('-_8=', '+/8', 'a', '-_9'):
            with self.subTest(bad):
                with self.assertRaises(ValueError):
                    wire.b64u_decode(bad)


# =====================================================================================================================
# Contract v0.3 tables, and their parity with Pebble's own code (the checkout is read, never changed)
# =====================================================================================================================

PEBBLE = os.environ.get('PEBBLE_CHECKOUT', '')  # a Pebble checkout, read only; without one the parity tests skip


def pebble_source(relative):
    if not PEBBLE:
        return None
    path = os.path.join(PEBBLE, relative)
    if not os.path.isfile(path):
        return None
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def function_block(source, header):
    start = source.index(header)
    following = re.search(r'\n    def |\ndef ', source[start + len(header):])
    return source[start:start + len(header) + (following.start() if following else len(source))]


class ContractTableTests(unittest.TestCase):
    def test_phone_allowlist_is_allowed_minus_excluded(self):
        allowed = set(mock_bridge.PHONE_ALLOWED)
        self.assertEqual(allowed & set(wire.PHONE_EXCLUDED), set())
        self.assertFalse([m for m in allowed if m.startswith('plugin_package_') or
                          (m.startswith('connector_') and m != 'connector_status')])
        self.assertIn('connector_status', allowed)
        self.assertEqual(set(mock_bridge.METHODS) - allowed, set(wire.REMOTE_METHODS))
        self.assertLessEqual(mock_bridge.SIMULATED, allowed)

    def test_the_simulated_methods_are_exactly_what_the_mock_offers(self):
        sim = mock_bridge.SimPebble(lambda name, data: None)
        self.assertEqual(set(sim.methods()), mock_bridge.SIMULATED)

    def test_elevated_and_unlock_classes(self):
        elevated = set(mock_bridge.ELEVATED)
        self.assertIn('remote.unlock', elevated)
        self.assertIn('setting:permissions', elevated)
        self.assertNotIn('setting', elevated)
        self.assertNotIn('remote.keep_awake', elevated)  # R3
        offered = set(mock_bridge.METHODS)
        self.assertEqual({m for m in elevated if not m.startswith('setting:')}, offered & set(wire.ELEVATED_ALWAYS))
        self.assertLessEqual(set(wire.UNLOCK_FREE), set(wire.READ_ONLY))
        self.assertEqual(set(wire.READ_ONLY) & set(wire.ELEVATED_ALWAYS), set())
        self.assertEqual(len(wire.UNLOCK_FREE), 15)  # C1's 14 reads, and S-05's remote.lock

    def test_main_window_allowed_matches_pebble(self):
        source = pebble_source('src-tauri/src/main.rs')
        if source is None:
            self.skipTest('the Pebble checkout is not here')
        allowed = re.findall(r'"([^"]+)"', re.search(r'const ALLOWED: &\[&str\] = &\[(.*?)\];', source, re.S).group(1))
        native = re.findall(r'"([^"]+)"', re.search(r'const NATIVE_ONLY: &\[&str\] = &\[(.*?)\];', source, re.S).group(1))
        self.assertEqual(mock_bridge.MAIN_WINDOW_ALLOWED, allowed, 'main.rs ALLOWED changed: update the copy')
        self.assertEqual(set(wire.NATIVE_ONLY), set(native), 'main.rs NATIVE_ONLY changed: update remote_wire')

    def test_every_pebble_setting_key_is_classified(self):
        app = pebble_source('backend/pebble/app.py')
        settings_file = pebble_source('backend/pebble/settings_file.py')
        if app is None or settings_file is None:
            self.skipTest('the Pebble checkout is not here')
        block = function_block(app, '    def setting(self, key, value):')
        keys = set(re.findall(r"key\s*==\s*['\"]([a-z_]+)['\"]", block))
        for group in re.findall(r'key in [{(]([^})]*)[})]', block):
            keys |= set(re.findall(r"['\"]([a-z_]+)['\"]", group))
        if 'companion_settings.KEY' in block:
            keys.add('companion')
        self.assertGreaterEqual(len(keys), 10)
        self.assertEqual(keys - set(mock_bridge.SETTING_CLASSES), set(), 'a Pebble setting key is not classified')
        widening = set(re.findall(r"key\s*==\s*['\"]([a-z_]+)['\"]", function_block(settings_file, 'def widening(')))
        self.assertTrue(widening)
        self.assertEqual({k for k in widening & keys if mock_bridge.SETTING_CLASSES[k] != 'elevated'}, set(),
                         "a key Pebble's widening() covers is not elevated")
        sim = mock_bridge.SimPebble(lambda name, data: None)
        for key in mock_bridge.SETTING_CLASSES:  # the simulated Pebble accepts every classified key
            value = sim.notification_settings if key == 'notifications' else sim.settings[key]
            self.assertTrue(sim.setting(key, json.loads(json.dumps(value))), key)

    def test_v05_tables(self):
        opening = set(wire.OPEN_ON_MAC)
        self.assertEqual(len(wire.OPEN_ON_MAC), 9)
        self.assertEqual(opening & set(wire.PHONE_EXCLUDED), set())              # v0.5 allows them
        self.assertLessEqual(opening, set(wire.PHONE_EXCLUDED_V03))               # v0.3 kept them off
        self.assertEqual(set(wire.PHONE_EXCLUDED_V03) - set(wire.PHONE_EXCLUDED), opening)
        for method in wire.OPEN_ON_MAC:
            self.assertTrue(wire.phone_excluded(method, v05=False), method)
            self.assertFalse(wire.phone_excluded(method), method)
            self.assertIn(method, wire.ELEVATED_ALWAYS)                           # every one needs a proof
            self.assertIn(method, mock_bridge.METHODS)                            # and the mock offers it
            self.assertIn(method, mock_bridge.ELEVATED)                           # and lists it in welcome.elevated
            self.assertNotIn(method, wire.READ_ONLY)
        for method in ('attach', 'chatgpt_start', 'mod_install', 'extension_add', 'plan_credential_save',
                       'memory_archive_export_to', 'storage_reveal'):             # still Mac-only
            self.assertTrue(wire.phone_excluded(method), method)
        # remote.folders: offered, idem optional (a read), but not one of C1's reads: it needs the unlock
        self.assertIn('remote.folders', wire.REMOTE_METHODS)
        self.assertIn('remote.folders', mock_bridge.METHODS)
        self.assertIn('remote.folders', wire.READ_ONLY)
        self.assertNotIn('remote.folders', wire.UNLOCK_FREE)
        self.assertNotIn('remote.folders', mock_bridge.ELEVATED)
        self.assertEqual(wire.FOLDERS_LIMIT, 500)
        # set_workspace and new_chat are elevated only for a new folder, so welcome.elevated cannot list them
        self.assertNotIn('set_workspace', mock_bridge.ELEVATED)
        self.assertNotIn('new_chat', mock_bridge.ELEVATED)

    def test_protected_folders_match_pebbles_shell_policy(self):
        """The protected list is copied from Pebble's Shell sandbox (D92); this reads the checkout's source as text and
        compares, without running anything from it."""
        source = pebble_source('backend/pebble/shell_policy.py')
        if source is None:
            self.skipTest('the Pebble checkout is not here')
        import ast
        found = {}
        for node in ast.parse(source).body:
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                found[node.targets[0].id] = node.value
        self.assertEqual(wire.PROTECTED_HOME, ast.literal_eval(found['PROTECTED_HOME']),
                         "shell_policy.PROTECTED_HOME changed: update remote_wire's copy")
        self.assertEqual(wire.PROTECTED_PREFIX, ast.literal_eval(found['PROTECTED_PREFIX']))
        compiled = found['PROTECTED_NAME']  # re.compile(<pattern>, re.I)
        self.assertEqual(wire.PROTECTED_NAME.pattern, ast.literal_eval(compiled.args[0]),
                         "shell_policy.PROTECTED_NAME changed: update remote_wire's copy")
        self.assertEqual(ast.unparse(compiled.args[1]), 're.I')
        self.assertTrue(wire.PROTECTED_NAME.flags & re.I)

    def test_protected_entry_follows_shell_policy_rules(self):
        home = '/h'
        pure = dict(realpath=wire.posixpath.normpath, exists=lambda path: True)
        for path, entry in (('/h/.ssh', '~/.ssh'), ('/h/.SSH/keys', '~/.ssh'), ('/h/PebbleBackups/x', '~/PebbleBackups'),
                            ('/h/Documents/Pebble', '~/Documents/Pebble'), ('/h/Library/Safari', '~/Library/Safari'),
                            ('/h/.claude-other/a', '~/.claude-other'), ('/h/.claude.json', '~/.claude.json'),
                            ('/h/Work/prod.key', 'prod.key'), ('/h/secrets', 'secrets'), ('/h/a/.env', '.env')):
            self.assertEqual(wire.protected_entry(home, path, **pure), entry, path)
        for path in ('/h/Projects', '/h/Library', '/h/Documents', '/h/Documents/Notes', '/h/claude', '/h/a/secrets/b',
                     '/elsewhere/.ssh', '/h'):
            self.assertIsNone(wire.protected_entry(home, path, **pure), path)
        self.assertEqual(wire.protected_entry(home, '/h/mine/x', ['/h/mine'], **pure), '/h/mine')


class ScreenshotTests(unittest.TestCase):
    def test_test_pattern_is_a_well_formed_png(self):
        import zlib
        png = mock_bridge.test_pattern_png(320, 200, mirrored=True)
        self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
        position, chunks = 8, {}
        while position < len(png):
            size = int.from_bytes(png[position:position + 4], 'big')
            kind, body = png[position + 4:position + 8], png[position + 8:position + 8 + size]
            crc = int.from_bytes(png[position + 8 + size:position + 12 + size], 'big')
            self.assertEqual(zlib.crc32(kind + body), crc, kind)
            chunks[kind] = body
            position += 12 + size
        self.assertEqual(chunks[b'IHDR'][:8], (320).to_bytes(4, 'big') + (200).to_bytes(4, 'big'))
        self.assertEqual(len(zlib.decompress(chunks[b'IDAT'])), 200 * (1 + 3 * 320))
        self.assertIn(b'IEND', chunks)

    @unittest.skipUnless(os.access('/usr/bin/sips', os.X_OK), 'sips is not available')
    def test_test_screens_are_jpegs_of_their_size(self):
        with tempfile.TemporaryDirectory() as folder:
            screens = mock_bridge.make_test_screens(((0, 320, 200), (1, 400, 300)), folder)
            self.assertEqual(os.listdir(folder), [])  # nothing is left behind
        self.assertEqual(wire.jpeg_size(screens[0]), (320, 200))
        self.assertEqual(wire.jpeg_size(screens[1]), (400, 300))
        with self.assertRaises(ValueError):
            wire.jpeg_size(b'\x89PNG\r\n\x1a\n')


# =====================================================================================================================
# The bridge's event pipeline and the simulated Pebble
# =====================================================================================================================

class StubIdentity:
    bid, pin = 'b-test', 'pin-test'


class BridgeLogicTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.folder = tempfile.TemporaryDirectory()
        registry = mock_bridge.Registry(os.path.join(self.folder.name, 'devices.json'))
        self.bridge = mock_bridge.Bridge(StubIdentity(), registry, name='Test Mac', speed=50)

    async def asyncTearDown(self):
        for task in list(self.bridge.sim.tasks.values()):
            task.cancel()
        self.folder.cleanup()

    def frames(self):
        return [json.loads(frame) for _, _, frame in self.bridge.buffer]

    async def test_tokens_merge_within_30_ms_and_keep_order(self):
        bridge = self.bridge
        bridge.pebble_event('token', {'chat_id': 'c', 'id': 'm', 'text': 'Hel'})
        bridge.pebble_event('token', {'chat_id': 'c', 'id': 'm', 'text': 'lo'})
        bridge.pebble_event('token', {'chat_id': 'c', 'id': 'other', 'text': '!'})   # another reply: not merged
        bridge.pebble_event('progress', {'chat_id': 'c', 'run_id': 'r', 'label': 'x', 'kind': 'working'})
        await asyncio.sleep(0.05)
        bridge.pebble_event('reasoning', {'chat_id': 'c', 'run_id': 'r', 'attempt_id': 'a', 'delta': 'one '})
        bridge.pebble_event('reasoning', {'chat_id': 'c', 'run_id': 'r', 'attempt_id': 'a', 'delta': 'two'})
        await asyncio.sleep(0.05)  # the 30 ms timer sends it
        bridge.pebble_event('token', {'chat_id': 'c', 'id': 'm', 'text': 'A'})
        await asyncio.sleep(0.045)
        bridge.pebble_event('token', {'chat_id': 'c', 'id': 'm', 'text': 'B'})  # after the window: its own event
        await asyncio.sleep(0.05)
        frames = self.frames()
        self.assertEqual([f['seq'] for f in frames], list(range(1, len(frames) + 1)))
        self.assertEqual([(f['event'], f['data'].get('text', f['data'].get('delta'))) for f in frames],
                         [('token', 'Hello'), ('token', '!'), ('progress', None), ('reasoning', 'one two'),
                          ('token', 'A'), ('token', 'B')])

    async def test_resume_window(self):
        bridge = self.bridge
        for index in range(3):
            bridge.publish('settings', {'n': index})
        self.assertTrue(bridge.can_resume({'epoch': bridge.epoch, 'seq': 0}))
        self.assertTrue(bridge.can_resume({'epoch': bridge.epoch, 'seq': 3}))
        self.assertFalse(bridge.can_resume({'epoch': bridge.epoch, 'seq': 4}))
        self.assertFalse(bridge.can_resume({'epoch': 'e-old', 'seq': 1}))
        self.assertFalse(bridge.can_resume({'epoch': bridge.epoch, 'seq': '1'}))
        self.assertFalse(bridge.can_resume(None))
        bridge.buffer.popleft()  # seq 1 is gone: a phone at seq 0 can no longer resume
        self.assertFalse(bridge.can_resume({'epoch': bridge.epoch, 'seq': 0}))
        self.assertTrue(bridge.can_resume({'epoch': bridge.epoch, 'seq': 1}))

    def paired_device(self):
        device_key, approve_key = wire.SigningKey(), wire.SigningKey()
        record = self.bridge.registry.add({'name': 'Test iPhone'}, device_key.x963_b64u, approve_key.x963_b64u)
        return record['device_id'], approve_key

    async def test_proofs_are_bound_remembered_and_unlock(self):
        bridge = self.bridge
        device, approve = self.paired_device()
        conn, other = mock_bridge.Conn(bridge, None, 1), mock_bridge.Conn(bridge, None, 2)
        conn.device = other.device = device

        def frame(request_id, idem, nonce=None):
            ts = wire.now_ms()
            transcript = wire.t_proof(bridge.bid, device, bridge.epoch, nonce or conn.nonce, request_id, idem,
                                      'remote.unlock', '{}', ts)
            return {'t': 'req', 'id': request_id, 'method': 'remote.unlock', 'params_json': '{}', 'idem': idem,
                    'proof': {'ts': ts, 'sig': wire.b64u(approve.sign(transcript))}}

        self.assertFalse(bridge.is_unlocked(device))
        good = frame('r1', 'i1')
        self.assertTrue(bridge.check_proof(conn, good, 'remote.unlock', False, 'i1'))
        self.assertTrue(bridge.is_unlocked(device))
        self.assertTrue(bridge.is_unlocked(device) and other.device == device)  # the device, not the connection
        # C2: an accepted signature again, under another id too, and its (r, n - s) twin, which is a valid signature
        self.assertFalse(bridge.check_proof(conn, dict(good, id='r2'), 'remote.unlock', False, 'i1'))
        r, s = wire.der_decode_signature(wire.b64u_decode(good['proof']['sig']))
        twin = dict(good, proof=dict(good['proof'], sig=wire.b64u(wire.der_encode_signature(r, wire.N - s))))
        self.assertFalse(bridge.check_proof(conn, twin, 'remote.unlock', False, 'i1'))
        # bound to this connection's nonce, to the idem, and to an unused id
        self.assertFalse(bridge.check_proof(other, frame('r3', 'i3'), 'remote.unlock', False, 'i3'))
        self.assertFalse(bridge.check_proof(conn, frame('r4', 'i4'), 'remote.unlock', False, 'i5'))
        self.assertFalse(bridge.check_proof(conn, frame('r5', 'i5'), 'remote.unlock', True, 'i5'))
        self.assertTrue(bridge.check_proof(conn, frame('r6', 'i6'), 'remote.unlock', False, 'i6'))
        bridge.unlocked[device] = (time.monotonic() - 1, 0)  # the window lapses
        self.assertFalse(bridge.is_unlocked(device))

    async def test_handshake_limit(self):
        bridge = self.bridge
        self.assertTrue(all(bridge.admit('192.168.1.50') for _ in range(10)))
        self.assertFalse(bridge.admit('192.168.1.50'))
        self.assertTrue(bridge.admit('192.168.1.51'))  # per source address
        self.assertTrue(all(bridge.admit('127.0.0.1') for _ in range(30)))  # loopback is exempt
        bridge.handshakes['192.168.1.50'] = deque([time.monotonic() - 61] * 10)
        self.assertTrue(bridge.admit('192.168.1.50'))  # a minute later
        bridge.limit_loopback = True
        self.assertTrue(all(bridge.admit('::1') for _ in range(10)))
        self.assertFalse(bridge.admit('::1'))

    async def test_devices_event_is_the_methods_array_per_phone(self):
        bridge = self.bridge
        first, _ = self.paired_device()
        second, _ = self.paired_device()
        bridge.devices_event()
        _, _, frame = bridge.buffer[-1]
        for device in (first, second):
            data = json.loads(frame(device))['data']
            self.assertEqual({d['device_id'] for d in data}, {first, second})
            self.assertEqual([d['current'] for d in data], [d['device_id'] == device for d in data])

    async def test_every_event_is_forwarded_but_native_export_pdf(self):
        self.bridge.pebble_event('native_export_pdf', {'chat_id': 'c', 'export_id': 'x'})
        self.bridge.pebble_event('make_room', {})
        self.bridge.pebble_event('memory_forget', {'chat_id': 'c'})
        self.assertEqual([f['event'] for f in self.frames()], ['make_room', 'memory_forget'])

    async def test_watchdog_closes_a_silent_connection(self):
        self.bridge.idle_timeout = 0.4

        class SilentSocket:
            last_received = time.monotonic()

        conn = mock_bridge.Conn(self.bridge, SilentSocket(), 99)
        conn.device = 'd-test'
        task = asyncio.create_task(self.bridge.watchdog(conn))
        await asyncio.sleep(0.9)
        self.assertEqual(conn.closing, (wire.CLOSE_GOING_AWAY, 'silent too long'))
        task.cancel()

    async def test_the_watchdog_leaves_a_pairing_that_waits_for_the_person_alone(self):
        """X-1: up to two minutes of silence from a phone that waits for the Mac's confirmation is not a dead connection
        (30 s to authenticate, 45 s silent): the confirmation's own timeout ends the wait."""
        self.bridge.idle_timeout = 0.4

        class SilentSocket:
            last_received = time.monotonic()

        conn = mock_bridge.Conn(self.bridge, SilentSocket(), 97)
        conn.confirming = True
        task = asyncio.create_task(self.bridge.watchdog(conn))
        await asyncio.sleep(0.9)
        self.assertIsNone(conn.closing)  # silent for twice the idle time, and no device yet, but it is not closed
        conn.confirming = False
        await asyncio.sleep(0.9)
        self.assertEqual(conn.closing, (wire.CLOSE_GOING_AWAY, 'silent too long'))
        task.cancel()

    async def test_a_pairing_that_waits_ignores_what_the_phone_sends_meanwhile(self):
        sent = []
        conn = mock_bridge.Conn(self.bridge, None, 96)
        conn.confirming = True
        conn.send = sent.append
        await self.bridge.on_text(conn, json.dumps({'t': 'hello', 'v': 1, 'device_id': 'd-x', 'sig': 'AA'}))
        await self.bridge.on_text(conn, json.dumps({'t': 'pair', 'v': 1, 'code': 'x'}))
        self.assertEqual((sent, conn.closing), ([], None))

    async def test_backpressure_drops_the_connection(self):
        class StuckSocket:
            aborted = False

            def abort(self):
                self.aborted = True

        sock = StuckSocket()
        conn = mock_bridge.Conn(self.bridge, sock, 98)
        conn.live = True
        for _ in range(5):
            conn.send('x' * (1 << 20))
        self.assertTrue(sock.aborted)
        self.assertFalse(conn.live)
        self.assertEqual(len(conn.queue), 0)

    async def wait_for(self, predicate, timeout=5.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return True
            await asyncio.sleep(0.01)
        self.fail('timed out')

    async def test_card_flow_events_as_pebble_emits_them(self):
        sim = self.bridge.sim
        cid = next(c for c, row in sim.chats.items() if row['title'] == 'Fix the login redirect')
        sent = await sim.call('send', {'id': cid, 'text': 'Run the tests please'})
        run_id = sent['run_id']
        await self.wait_for(lambda: sim.runs[run_id]['state'] == 'waiting_approval' and not sim.active)
        card = next(a for a in sim.actions[cid] if a['status'] == 'pending')
        self.assertEqual((card['kind'], card['payload']['command']), ('command', 'npm test'))
        with self.assertRaises(mock_bridge.PebbleError):
            await sim.call('approve_simple', {'id': cid, 'action_id': card['id']})  # not a simple card
        result = await sim.call('approve', {'id': cid, 'action_id': card['id']})
        self.assertEqual(result['exit_code'], 0)
        await self.wait_for(lambda: sim.runs[run_id]['state'] == 'completed' and not sim.active)
        await asyncio.sleep(0.05)
        events = [(f['event'], f['data']) for f in self.frames()]
        names = [name for name, _ in events]
        states = [data['state'] for name, data in events if name == 'run']
        self.assertEqual(states, ['queued', 'running', 'waiting_approval', 'queued', 'running', 'completed'])
        for name in ('progress', 'token', 'actions', 'usage', 'complete', 'idle', 'activity', 'stream'):
            self.assertIn(name, names)
        progress = [data for name, data in events if name == 'progress']
        self.assertIn({'chat_id': cid, 'run_id': run_id, 'label': 'Reviewing terminal command', 'kind': 'working',
                       'tool': 'RunCommand', 'activity': 'running'}, progress)
        with self.assertRaises(mock_bridge.PebbleError) as refused:
            await sim.call('approve', {'id': cid, 'action_id': card['id']})
        self.assertEqual(refused.exception.message, 'This action is no longer awaiting approval.')

    async def test_question_flow_and_validation(self):
        sim = self.bridge.sim
        question = next(q for q in sim.questions.values() if q['status'] == 'pending')
        cid = question['chat_id']
        with self.assertRaises(mock_bridge.PebbleError):
            await sim.call('question_answer', {'id': cid, 'question_id': question['id'], 'revision': 2,
                                               'answers': {'beds': {'option_id': 'front'}}})
        with self.assertRaises(mock_bridge.PebbleError):
            await sim.call('question_answer', {'id': cid, 'question_id': question['id'], 'revision': 1,
                                               'answers': {'beds': {'option_id': 'nowhere'}}})
        answer = await sim.call('question_answer', {'id': cid, 'question_id': question['id'], 'revision': 1,
                                                    'answers': {'beds': {'option_id': 'back'}}})
        self.assertEqual(answer['message'], {'id': 'answer-' + question['id'], 'role': 'user',
                                             'content': 'The back beds'})
        await self.wait_for(lambda: sim.runs[question['run_id']]['state'] == 'completed')
        events = [f['event'] for f in self.frames()]
        self.assertIn('plan', events)

    async def test_stop_and_steer(self):
        sim = self.bridge.sim
        sim.speed = 1.0
        cid = (await sim.call('new_chat', {}))['id']
        sent = await sim.call('send', {'id': cid, 'text': 'Take the slow route'})
        await self.wait_for(lambda: sim.runs[sent['run_id']]['state'] == 'running')
        steer = await sim.call('send', {'id': cid, 'text': 'Keep it short'})
        self.assertTrue(steer['steering'])
        with self.assertRaises(mock_bridge.PebbleError):
            await sim.call('send', {'id': next(c for c in sim.chats if c != cid), 'text': 'another'})
        self.assertTrue(await sim.call('cancel', {'id': cid}))
        await self.wait_for(lambda: sim.runs[sent['run_id']]['state'] == 'stopped' and not sim.active)
        self.assertIn('stopped', [f['event'] for f in self.frames()])


# =====================================================================================================================
# Proposal v0.5: folders, connecting a project, opening things on the Mac
# =====================================================================================================================

def make_tree(root):
    """A small home folder for remote.folders: projects (one with a worktree's .git file), folders that must stay out of
    the listing, links, and a file. Returns its real path."""
    os.makedirs(root, exist_ok=True)
    root = os.path.realpath(root)
    for relative in ('Projects/app/.git', 'Projects/lib', 'Projects/Zeta', 'Projects/alpha', 'Projects/wt',
                     'Work/notes', 'Work/prod.key', 'Documents/Notes', 'Documents/Pebble', 'Archive', 'beta',
                     '.ssh', '.hidden/inner', '.claude-other/x', 'PebbleBackups/old', 'Library/Safari', 'secrets/a',
                     'mock-state'):
        os.makedirs(os.path.join(root, relative), exist_ok=True)
    with open(os.path.join(root, 'Projects', 'wt', '.git'), 'w') as handle:  # a worktree's .git is a file
        handle.write('gitdir: ../app/.git/worktrees/wt\n')
    with open(os.path.join(root, 'notes.txt'), 'w') as handle:
        handle.write('a file: never listed\n')
    os.symlink('/usr', os.path.join(root, 'usrlink'))                              # a link out of home
    os.symlink(os.path.join(root, 'Projects'), os.path.join(root, 'ProjectsLink'))  # a link that stays inside
    if hasattr(os, 'chflags'):  # macOS's hidden flag, which ~/Library has
        os.chflags(os.path.join(root, 'Library'), stat.UF_HIDDEN)
    return root


HOME_FOLDERS = ['Archive', 'beta', 'Documents', 'Projects', 'Work']  # what make_tree's home shows, by name, any case
LEFT_OUT = ('.ssh', '.hidden', '.claude-other', 'PebbleBackups', 'secrets', 'mock-state', 'usrlink', 'ProjectsLink',
            'notes.txt')
BANNED_WORDS = re.compile(r'\b(inference|receipts?|host|runtime|capacity|E-B1)\b', re.I)  # Pebble's list (BannedWords)


class FoldersTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = make_tree(os.path.join(self.folder.name, 'home'))
        self.folders = mock_bridge.Folders(self.root, extra_protected=[os.path.join(self.root, 'mock-state')])

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def refused(self, path):
        with self.assertRaises(mock_bridge.FolderRefused) as caught:
            self.folders.listing(path)
        return caught.exception

    def test_the_listing_has_exactly_the_proposals_shape(self):
        home = self.folders.listing()
        self.assertEqual(set(home), {'home', 'path', 'parent', 'folders'})
        self.assertEqual((home['home'], home['path'], home['parent']), (self.root, self.root, None))
        self.assertEqual([row['name'] for row in home['folders']], HOME_FOLDERS)  # by name, whatever the case
        for row in home['folders']:
            self.assertEqual(set(row), {'name', 'path', 'is_project'})
            self.assertEqual(row['path'], self.path(row['name']))
            self.assertIs(type(row['is_project']), bool)
        self.assertEqual(self.folders.listing(None), home)

    def test_going_down_and_up_and_projects(self):
        projects = self.folders.listing(self.path('Projects'))
        self.assertEqual((projects['path'], projects['parent'], projects['home']),
                         (self.path('Projects'), self.root, self.root))
        # is_project is true when .git exists: a folder, or the file a worktree has
        self.assertEqual([(row['name'], row['is_project']) for row in projects['folders']],
                         [('alpha', False), ('app', True), ('lib', False), ('wt', True), ('Zeta', False)])
        deeper = self.folders.listing(self.path('Projects', 'app'))
        self.assertEqual((deeper['parent'], deeper['folders']), (self.path('Projects'), []))
        self.assertEqual(self.folders.listing(projects['parent']), self.folders.listing())
        self.assertEqual(self.folders.listing(self.path('Projects') + '/'), projects)  # a trailing slash is the same

    def test_hidden_protected_and_own_folders_links_and_files_are_left_out(self):
        shown = {row['name'] for row in self.folders.listing()['folders']}
        for name in LEFT_OUT:
            self.assertNotIn(name, shown, name)
        if hasattr(os, 'chflags'):
            self.assertNotIn('Library', shown)  # hidden by macOS's flag, as the Finder hides it
        # below home too: Documents/Pebble is on the protected list, Work/prod.key is a secret by its name
        self.assertEqual([row['name'] for row in self.folders.listing(self.path('Documents'))['folders']], ['Notes'])
        self.assertEqual([row['name'] for row in self.folders.listing(self.path('Work'))['folders']], ['notes'])

    def test_a_path_outside_home_or_with_dots_or_a_link_is_not_allowed(self):
        for path in ('/', '/etc', '/usr', os.path.dirname(self.root), self.root + '/..', self.root + '/../..',
                     self.path('Projects', '..', '..'), self.path('Projects', '..', 'Documents'),
                     self.root + '//Projects', self.path('usrlink'), self.path('usrlink', 'bin'),
                     self.path('ProjectsLink'), self.path('ProjectsLink', 'app')):
            with self.subTest(path=path.replace(self.root, '~')):
                error = self.refused(path)
                self.assertEqual(error.code, 'not_allowed')
                self.assertEqual(error.words, mock_bridge.FOLDER_WORDS['outside'])
                self.assertFalse(self.folders.listable(path))

    def test_a_path_that_is_itself_a_symbolic_link_is_not_allowed(self):
        """claude-w's 10:53 addition: a `path` that is itself a link, or that resolves outside home (or the
        --folders-root), gets not_allowed, whatever the link leads to."""
        os.symlink(self.path('Work'), self.path('to-work'))                  # inside home, to a folder inside home
        os.symlink('/usr', self.path('to-usr'))                              # out of home
        os.symlink(self.path('to-work'), self.path('chain'))                 # a link to a link
        os.symlink(self.path('nowhere'), self.path('dangling'))              # to nothing
        os.symlink(self.path('notes.txt'), self.path('to-file'))             # to a file
        os.symlink(self.path('Documents', 'Notes'), self.path('Work', 'deep-link'))  # a link below a folder
        links = ['to-work', 'to-usr', 'chain', 'dangling', 'to-file', 'Work/deep-link']
        for name in links:
            real = self.path(*name.split('/'))
            for spelling in (real, real + '/', os.path.join(real, 'x')):  # the link, with a slash, and a path below it
                with self.subTest(spelling=spelling.replace(self.root, '~')):
                    error = self.refused(spelling)
                    self.assertEqual((error.code, error.words), ('not_allowed', mock_bridge.FOLDER_WORDS['outside']))
                    self.assertFalse(self.folders.listable(spelling))
        shown = {row['name'] for row in self.folders.listing()['folders']}
        self.assertEqual(shown & {'to-work', 'to-usr', 'chain', 'dangling', 'to-file'}, set())  # and none is listed
        self.assertEqual([row['name'] for row in self.folders.listing(self.path('Work'))['folders']], ['notes'])

    def test_a_folders_root_reached_through_a_link_is_its_real_path_only(self):
        """The root of a test tree is spelled as its real path too: a path through a link to the root is not allowed."""
        through = os.path.join(self.folder.name, 'root-link')
        os.symlink(self.root, through)
        folders = mock_bridge.Folders(through)
        self.assertEqual(folders.home, self.root)
        self.assertEqual(folders.listing()['home'], self.root)
        for path in (through, os.path.join(through, 'Projects')):
            with self.assertRaises(mock_bridge.FolderRefused) as caught:
                folders.listing(path)
            self.assertEqual(caught.exception.code, 'not_allowed')
        self.assertEqual(folders.listing(self.path('Projects'))['path'], self.path('Projects'))

    def test_hidden_and_protected_paths_are_refused_whether_or_not_they_exist(self):
        for relative in ('.ssh', '.ssh/keys', '.pebble', '.hidden', '.hidden/inner', '.claude-other', 'PebbleBackups',
                         'PebbleBackups/old', 'Documents/Pebble', 'Library/Safari', 'Library/Keychains', 'secrets',
                         'secrets/a', 'Work/prod.key', 'mock-state', 'Projects/.git', 'Projects/app/.git'):
            with self.subTest(relative=relative):
                error = self.refused(self.path(*relative.split('/')))
                self.assertEqual(error.code, 'not_allowed')
                self.assertEqual(error.words, mock_bridge.FOLDER_WORDS['private'])
                self.assertFalse(self.folders.listable(self.path(*relative.split('/'))))

    def test_a_path_that_is_not_an_absolute_string_is_a_bad_request(self):
        for path in (5, True, ['/'], {'p': 1}, '', 'Projects', './Projects', '~', self.root + '\x00', '/' + 'a' * 5000):
            with self.subTest(path=repr(path)[:20]):
                error = self.refused(path)
                self.assertEqual((error.code, error.words), ('bad_request', mock_bridge.ERRORS['bad_request']))
                self.assertFalse(self.folders.listable(path))

    def test_a_folder_that_is_not_there_is_refused_in_words_without_a_code(self):
        for path in (self.path('nope'), self.path('Projects', 'nope', 'deeper'), self.path('notes.txt')):
            error = self.refused(path)
            self.assertEqual((error.code, error.words), (None, mock_bridge.FOLDER_WORDS['missing']))
            self.assertFalse(self.folders.listable(path))

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root can read every folder')
    def test_a_folder_that_cannot_be_read_is_refused_in_words(self):
        locked = self.path('Archive')
        os.chmod(locked, 0)
        self.addCleanup(os.chmod, locked, 0o755)
        error = self.refused(locked)
        self.assertEqual((error.code, error.words), (None, mock_bridge.FOLDER_WORDS['unreadable']))

    def test_the_listing_stops_at_500_and_stays_sorted(self):
        big = self.path('Archive')
        for number in range(520):
            os.mkdir(os.path.join(big, 'd%03d' % number))
        names = [row['name'] for row in self.folders.listing(big)['folders']]
        self.assertEqual(names, ['d%03d' % n for n in range(500)])
        self.assertEqual(wire.FOLDERS_LIMIT, 500)

    def test_listable_is_exactly_what_the_listing_shows(self):
        """`set_workspace` and `new_chat` accept a new folder only when `remote.folders` would list it: walk the tree,
        and every folder shown can be connected while everything else cannot."""
        seen, queue = set(), [self.root]
        while queue:
            listing = self.folders.listing(queue.pop())
            for row in listing['folders']:
                seen.add(row['path'])
                queue.append(row['path'])
        self.assertIn(self.path('Projects', 'app'), seen)
        for path in seen:
            self.assertTrue(self.folders.listable(path), path)
        everything = {os.path.join(top, name) for top, names, _ in os.walk(self.root, followlinks=False)
                      for name in names}
        for path in everything - seen:
            self.assertFalse(self.folders.listable(path), path.replace(self.root, '~'))
        self.assertFalse(self.folders.listable(self.root))  # the home folder itself is never one of the folders
        self.assertFalse(self.folders.listable(None))
        self.assertFalse(self.folders.listable(7))

    def test_the_default_is_the_home_folder_of_the_user(self):
        with mock.patch.dict(os.environ, {'HOME': self.root}):
            default = mock_bridge.Folders()
        self.assertEqual(default.home, self.root)
        # nothing is protected but Pebble's list: the mock's own state folder is only left out when the bridge says so
        self.assertEqual([row['name'] for row in default.listing()['folders']],
                         sorted(HOME_FOLDERS + ['mock-state'], key=str.casefold))

    def test_a_folder_name_that_cannot_be_sent_is_left_out(self):
        class Entry:  # what os.scandir gives for a name that is not valid UTF-8 (Python's surrogate escape)
            def __init__(self, name):
                self.name = name

            def is_symlink(self):
                return False

            def is_dir(self, follow_symlinks=True):
                return True

            def stat(self, follow_symlinks=True):
                return os.lstat(self.path_)

        bad, good = Entry(os.fsdecode(b'bad-\xff')), Entry('good')
        bad.path_ = good.path_ = self.root
        self.assertIsNone(self.folders._row(self.root, bad))
        self.assertEqual(self.folders._row(self.root, good)['name'], 'good')


class InProcessPhone:
    """A software phone on a bridge in this process: its two keys, its connection, and calls made as the wire carries
    them (a plain request, or an elevated one with a proof)."""

    def __init__(self, bridge):
        self.bridge = bridge
        self.device_key, self.approve_key = wire.SigningKey(), wire.SigningKey()
        record = bridge.registry.add({'name': 'Test iPhone'}, self.device_key.x963_b64u, self.approve_key.x963_b64u)
        self.device = record['device_id']
        self.conn = mock_bridge.Conn(bridge, None, 1)
        self.conn.device = self.device
        self.count = 0
        bridge.buckets[self.device] = mock_bridge.TokenBucket(10 ** 6, 10 ** 6)  # these tests are not about the rate limit

    def unlock(self, seconds=900):
        self.bridge.unlocked[self.device] = (time.monotonic() + seconds, wire.now_ms() + seconds * 1000)

    def lock(self):
        self.bridge.unlocked.pop(self.device, None)

    async def call(self, method, params=None, elevated=False, idem=True):
        self.count += 1
        request_id, key = 'r%d' % self.count, str(uuid.uuid4())
        if elevated:
            text = json.dumps(params or {}, separators=(',', ':'))
            ts = wire.now_ms()
            transcript = wire.t_proof(self.bridge.bid, self.device, self.bridge.epoch, self.conn.nonce, request_id,
                                      key, method, text, ts)
            frame = {'t': 'req', 'id': request_id, 'method': method, 'params_json': text, 'idem': key,
                     'proof': {'ts': ts, 'sig': wire.b64u(self.approve_key.sign(transcript))}}
        else:
            frame = {'t': 'req', 'id': request_id, 'method': method, 'params': {} if params is None else params}
            if idem:
                frame['idem'] = key
        await self.bridge.on_req(self.conn, frame)
        answers = [json.loads(text) for text in self.conn.queue]
        self.conn.queue.clear()
        self.conn.queued = 0
        return next(a for a in answers if a.get('id') == request_id)


class RemoteLockTests(unittest.IsolatedAsyncioTestCase):
    """S-05 (claude-w's 10:49 answer, item 4): `remote.lock` is a read, {} to {}, that ends the device's unlock at once."""

    async def asyncSetUp(self):
        self.folder = tempfile.TemporaryDirectory()
        registry = mock_bridge.Registry(os.path.join(self.folder.name, 'devices.json'))
        self.bridge = mock_bridge.Bridge(StubIdentity(), registry, name='Test Mac', speed=50)
        self.phone, self.other = InProcessPhone(self.bridge), InProcessPhone(self.bridge)

    async def asyncTearDown(self):
        for task in list(self.bridge.sim.tasks.values()):
            task.cancel()
        self.folder.cleanup()

    async def test_remote_lock_ends_the_unlock_at_once(self):
        phone = self.phone
        phone.unlock()
        self.assertTrue((await phone.call('new_chat', {}))['ok'])
        answer = await phone.call('remote.lock', {}, idem=False)
        self.assertEqual((answer['ok'], answer['result']), (True, {}))
        self.assertFalse(self.bridge.is_unlocked(phone.device))
        self.assertEqual((await phone.call('new_chat', {}))['code'], 'unlock_required')
        self.assertEqual((await phone.call('model_profiles', {}))['code'], 'unlock_required')
        self.assertTrue((await phone.call('state', {}))['ok'])  # the reads still work
        self.assertTrue((await phone.call('remote.ping', {'ts': 1}))['ok'])

    async def test_remote_lock_is_a_read_needing_no_unlock_no_proof_and_no_idem(self):
        phone = self.phone
        self.assertIn('remote.lock', wire.UNLOCK_FREE)
        self.assertIn('remote.lock', wire.READ_ONLY)
        self.assertIn('remote.lock', mock_bridge.METHODS)
        self.assertNotIn('remote.lock', mock_bridge.ELEVATED)
        phone.lock()
        for idem in (False, True):  # locked already: it still answers {}, with or without a retry key
            answer = await phone.call('remote.lock', {}, idem=idem)
            self.assertEqual((answer['ok'], answer['result']), (True, {}), idem)
        self.assertNotEqual(self.bridge.needs_proof('remote.lock', {}), True)

    async def test_the_lock_is_one_devices_alone(self):
        self.phone.unlock()
        self.other.unlock()
        await self.phone.call('remote.lock', {}, idem=False)
        self.assertFalse(self.bridge.is_unlocked(self.phone.device))
        self.assertTrue(self.bridge.is_unlocked(self.other.device))

    async def test_an_elevated_call_unlocks_again_after_the_lock(self):
        phone = self.phone
        phone.unlock()
        await phone.call('remote.lock', {}, idem=False)
        answer = await phone.call('remote.unlock', {}, elevated=True)
        self.assertTrue(answer['ok'], answer)
        self.assertTrue((await phone.call('new_chat', {}))['ok'])


class V05BridgeTests(unittest.IsolatedAsyncioTestCase):
    """The bridge's rules for proposal v0.5, in this process: who may list folders, what needs a proof, and what the
    simulated Pebble does with the nine methods that open things on the Mac."""

    async def asyncSetUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = make_tree(os.path.join(self.folder.name, 'home'))
        registry = mock_bridge.Registry(os.path.join(self.folder.name, 'devices.json'))
        self.bridge = mock_bridge.Bridge(StubIdentity(), registry, name='Test Mac', speed=50, folders_root=self.root,
                                         state_dir=os.path.join(self.root, 'mock-state'))
        self.sim = self.bridge.sim
        self.phone = InProcessPhone(self.bridge)
        self.phone.unlock()
        self.project_chat = next(c for c, row in self.sim.chats.items() if row['workspace'] == mock_bridge.PROJECT)
        self.plain_chat = next(c for c, row in self.sim.chats.items() if row['workspace'] is None)

    async def asyncTearDown(self):
        for task in list(self.sim.tasks.values()):
            task.cancel()
        self.folder.cleanup()

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def workspace_of(self, chat_id):
        return self.sim.chats[chat_id]['workspace']

    # -- remote.folders ------------------------------------------------------------------------------------------------

    async def test_remote_folders_needs_the_unlock_and_answers_the_listing(self):
        phone = self.phone
        phone.lock()
        for idem in (True, False):  # a read: idem is optional, and the unlock is still needed
            answer = await phone.call('remote.folders', {}, idem=idem)
            self.assertEqual((answer['ok'], answer['code']), (False, 'unlock_required'))
        phone.unlock()
        for params, idem in (({}, True), ({}, False), ({'path': None}, False)):
            answer = await phone.call('remote.folders', params, idem=idem)
            self.assertTrue(answer['ok'], answer)
            self.assertEqual(set(answer['result']), {'home', 'path', 'parent', 'folders'})
            self.assertEqual([row['name'] for row in answer['result']['folders']], HOME_FOLDERS)
        deeper = await phone.call('remote.folders', {'path': self.path('Projects')}, idem=False)
        self.assertEqual((deeper['result']['path'], deeper['result']['parent']), (self.path('Projects'), self.root))
        # it needs no proof, and it is the bridge's own (the simulated Pebble need not be running)
        self.sim.running = False
        self.assertTrue((await phone.call('remote.folders', {}))['ok'])

    async def test_remote_folders_refusals_and_their_codes(self):
        phone = self.phone
        cases = [(self.root + '/..', 'not_allowed'), ('/', 'not_allowed'), (self.path('usrlink'), 'not_allowed'),
                 (self.path('.ssh'), 'not_allowed'), (self.path('PebbleBackups'), 'not_allowed'),
                 (7, 'bad_request'), ('Projects', 'bad_request'), (self.path('nope'), None)]
        for path, code in cases:
            answer = await phone.call('remote.folders', {'path': path})
            self.assertFalse(answer['ok'])
            self.assertEqual(answer.get('code'), code, answer)
            self.assertTrue(answer['error'])
            self.assertIsNone(BANNED_WORDS.search(answer['error']), answer['error'])
            self.assertNotIn(self.root, answer['error'])  # the words say nothing about the Mac's paths

    async def test_logs_never_carry_a_folder_name(self):
        mock_bridge.QUIET = False
        self.addCleanup(setattr, mock_bridge, 'QUIET', True)
        captured = io.StringIO()
        with contextlib.redirect_stderr(captured):
            await self.phone.call('remote.folders', {'path': self.path('Projects')})
            await self.phone.call('remote.folders', {'path': self.path('.ssh')})
        self.assertIn('remote.folders', captured.getvalue())
        for word in ('Projects', '.ssh', self.root, os.path.basename(self.root)):
            self.assertNotIn(word, captured.getvalue())

    # -- set_workspace and new_chat ------------------------------------------------------------------------------------

    def test_a_new_folder_is_the_only_thing_that_needs_a_proof(self):
        bridge = self.bridge
        new = self.path('Projects', 'app')
        for params, needs in (({'id': 'x', 'path': None}, False), ({'id': 'x', 'path': ''}, False),
                              ({'id': 'x', 'path': mock_bridge.PROJECT}, False), ({'id': 'x', 'path': new}, True),
                              ({'id': 'x', 'path': self.path('.ssh')}, True), ({'id': 'x', 'path': '/nope'}, True),
                              ({'id': 'x', 'path': ['a']}, True), ({'id': 'x', 'path': 7}, True),
                              ({'id': 'x', 'path': {'a': 1}}, True), ({'id': 'x'}, False)):
            self.assertEqual(bridge.needs_proof('set_workspace', params), needs, params)
        for params, needs in (({}, False), ({'workspace': None}, False), ({'workspace': mock_bridge.GARDEN}, False),
                              ({'workspace': new}, True), ({'workspace': ['a']}, True), ({'workspace': 0}, True)):
            self.assertEqual(bridge.needs_proof('new_chat', params), needs, params)
        self.assertIsNone(bridge.policy('set_workspace', {'id': 'x', 'path': mock_bridge.PROJECT}))
        self.assertIsNone(bridge.policy('set_workspace', {'id': 'x', 'path': new}))
        self.assertEqual(bridge.policy('set_workspace', {'id': 'x', 'path': self.path('.ssh')}),
                         mock_bridge.WORKSPACE_REFUSED)
        self.assertEqual(bridge.policy('new_chat', {'workspace': '/usr'}), mock_bridge.WORKSPACE_REFUSED)
        self.assertEqual(bridge.policy('new_chat', {'workspace': self.root}), mock_bridge.WORKSPACE_REFUSED)

    async def test_set_workspace_null_and_a_known_project_need_only_the_unlock(self):
        phone, chat = self.phone, self.plain_chat
        for state in ('locked', 'unlocked'):
            phone.lock() if state == 'locked' else phone.unlock()
            answer = await phone.call('set_workspace', {'id': chat, 'path': mock_bridge.PROJECT})
            if state == 'locked':
                self.assertEqual(answer['code'], 'unlock_required')
            else:
                self.assertTrue(answer['ok'], answer)
                self.assertEqual(answer['result']['workspace'], mock_bridge.PROJECT)  # Pebble's chat() answer
                self.assertEqual(self.workspace_of(chat), mock_bridge.PROJECT)
        answer = await phone.call('set_workspace', {'id': chat, 'path': None})  # back to the Companion
        self.assertTrue(answer['ok'], answer)
        self.assertIsNone(answer['result']['workspace'])
        self.assertIsNone(self.workspace_of(chat))

    async def test_a_new_folder_gets_proof_required_and_the_answer_hides_whether_it_exists(self):
        """Without a proof the answer is the same for a folder that is listed, one that is hidden and one that is not
        there, locked or unlocked: a phone that has not proved itself learns nothing about the Mac's folders."""
        phone, chat = self.phone, self.plain_chat
        for state in ('unlocked', 'locked'):
            phone.unlock() if state == 'unlocked' else phone.lock()
            for path in (self.path('Projects', 'app'), self.path('.ssh'), self.path('nope'), '/usr', self.root,
                         ['a'], 7):
                answer = await phone.call('set_workspace', {'id': chat, 'path': path})
                self.assertEqual((answer['ok'], answer.get('code')), (False, 'proof_required'), (state, path))
                self.assertEqual(answer['error'], mock_bridge.ERRORS['proof_required'])
        self.assertIsNone(self.workspace_of(chat))  # and nothing changed

    async def test_a_new_folder_with_a_proof_is_connected_when_the_listing_would_show_it(self):
        phone, chat = self.phone, self.plain_chat
        phone.lock()  # the proof itself unlocks the phone (C1)
        folder = self.path('Projects', 'app')
        answer = await phone.call('set_workspace', {'id': chat, 'path': folder}, elevated=True)
        self.assertTrue(answer['ok'], answer)
        self.assertEqual(answer['result']['workspace'], folder)
        self.assertEqual(self.workspace_of(chat), folder)
        self.assertTrue(self.bridge.is_unlocked(phone.device))
        # the folder is now a project a conversation uses: the next time it needs only the unlock
        other = await phone.call('set_workspace', {'id': self.project_chat, 'path': folder})
        self.assertTrue(other['ok'], other)
        self.assertEqual(self.workspace_of(self.project_chat), folder)

    async def test_a_link_is_not_allowed_in_remote_folders_set_workspace_and_new_chat(self):
        """claude-w's 10:53 addition, through the bridge: the path that is itself a link, or leads outside home."""
        phone, chat = self.phone, self.plain_chat
        os.symlink(self.path('Work'), self.path('to-work'))  # to a folder inside home
        os.symlink('/usr', self.path('to-usr'))              # out of home
        before = len(self.sim.chats)
        for link in (self.path('to-work'), self.path('to-usr'), self.path('to-work', 'notes'), self.path('to-usr', 'bin'),
                     self.path('to-work') + '/'):
            with self.subTest(link=link.replace(self.root, '~')):
                listed = await phone.call('remote.folders', {'path': link})
                self.assertEqual((listed['ok'], listed['code'], listed['error']),
                                 (False, 'not_allowed', mock_bridge.FOLDER_WORDS['outside']))
                for method, params in (('set_workspace', {'id': chat, 'path': link}), ('new_chat', {'workspace': link})):
                    plain = await phone.call(method, params)  # no proof: the same answer as for any new value
                    self.assertEqual((plain['ok'], plain['code']), (False, 'proof_required'), (method, link))
                    proved = await phone.call(method, params, elevated=True)
                    self.assertEqual((proved['ok'], proved['code'], proved['error']),
                                     (False, 'not_allowed', mock_bridge.WORKSPACE_REFUSED), (method, link))
        self.assertIsNone(self.workspace_of(chat))  # nothing was connected
        self.assertEqual(len(self.sim.chats), before)  # and no conversation was made
        self.assertNotIn('to-work', [row['name'] for row in (await phone.call('remote.folders', {}))['result']['folders']])

    async def test_a_folder_the_listing_would_not_show_is_refused_even_with_a_proof(self):
        phone, chat = self.phone, self.plain_chat
        for path in (self.path('.ssh'), self.path('.hidden', 'inner'), self.path('PebbleBackups', 'old'),
                     self.path('Documents', 'Pebble'), self.path('secrets'), self.path('mock-state'),
                     self.path('usrlink'), self.path('ProjectsLink', 'app'), self.root, '/usr', '/etc',
                     self.root + '/..', self.path('Projects', '..', 'Work'), self.path('nope'), self.path('notes.txt'),
                     ['a'], 7):
            answer = await phone.call('set_workspace', {'id': chat, 'path': path}, elevated=True)
            self.assertFalse(answer['ok'], path)
            self.assertEqual(answer['code'], 'not_allowed', (path, answer))
            self.assertEqual(answer['error'], mock_bridge.WORKSPACE_REFUSED)
            self.assertIsNone(self.workspace_of(chat))

    async def test_new_chat_keeps_the_workspace_and_a_new_folder_needs_the_same_proof(self):
        phone = self.phone
        for workspace in (None, mock_bridge.PROJECT, mock_bridge.GARDEN):
            answer = await phone.call('new_chat', {} if workspace is None else {'workspace': workspace})
            self.assertTrue(answer['ok'], answer)
            self.assertEqual(answer['result']['workspace'], workspace)  # kept as it is
            self.assertEqual(self.workspace_of(answer['result']['id']), workspace)
        folder = self.path('Projects', 'lib')
        for path in (folder, self.path('.ssh'), '/usr'):  # a new folder, with no proof: the same answer for all
            answer = await phone.call('new_chat', {'workspace': path})
            self.assertEqual((answer['ok'], answer['code']), (False, 'proof_required'))
        before = len(self.sim.chats)
        answer = await phone.call('new_chat', {'workspace': folder}, elevated=True)
        self.assertTrue(answer['ok'], answer)
        self.assertEqual(answer['result']['workspace'], folder)
        self.assertEqual(len(self.sim.chats), before + 1)
        for path in (self.path('.ssh'), '/usr', self.root, self.path('nope')):
            refused = await phone.call('new_chat', {'workspace': path}, elevated=True)
            self.assertEqual((refused['ok'], refused['code']), (False, 'not_allowed'), path)
        self.assertEqual(len(self.sim.chats), before + 1)  # none of those made a conversation
        # an empty conversation is not listed until it has a message (the draft stays off the Mac's list)
        state = (await phone.call('state', {}))['result']
        self.assertNotIn(answer['result']['id'], [chat['id'] for chat in state['chats']])

    async def test_new_chat_stores_a_new_folder_resolved_as_pebble_does(self):
        # Pebble stores Workspace(path).root; the bridge only lets a path through that is already its own real path
        folder = self.path('Projects', 'alpha')
        answer = await self.phone.call('new_chat', {'workspace': folder}, elevated=True)
        self.assertEqual(answer['result']['workspace'], os.path.realpath(folder))

    # -- opening things on the Mac -------------------------------------------------------------------------------------

    def open_calls(self):
        run_id = next(r for r, run in self.sim.runs.items() if run['chat_id'] == self.project_chat)
        return {
            'open_url': {'url': 'https://example.com/docs?page=2'},
            'open_app': {'id': self.project_chat, 'app_id': 'com.apple.Calculator'},
            'view_stage': {},
            'artifact_view_open': {'chat_id': self.project_chat, 'id': 'artifact-1', 'revision': 1},
            'browser_start': {},
            'browser_open_tab': {'url': 'https://example.com/'},
            'quiz_share': {'chat_id': self.project_chat, 'attempt_id': 'attempt-1'},
            'terminal_propose': {'id': self.project_chat, 'command': 'ls -la', 'network': False},
            'process_terminal': {'id': self.project_chat, 'run_id': run_id, 'process_id': 'process-1'},
        }

    async def test_the_nine_need_a_proof_and_the_simulated_pebble_opens_nothing(self):
        phone, calls = self.phone, self.open_calls()
        self.assertEqual(set(calls), set(wire.OPEN_ON_MAC))
        for method, params in calls.items():  # no proof, locked or not: proof_required, and nothing happens
            for state in ('locked', 'unlocked'):
                phone.lock() if state == 'locked' else phone.unlock()
                answer = await phone.call(method, params)
                self.assertEqual((answer['ok'], answer.get('code')), (False, 'proof_required'), (method, state))
        mock_bridge.QUIET = False
        self.addCleanup(setattr, mock_bridge, 'QUIET', True)
        captured = io.StringIO()
        with contextlib.redirect_stderr(captured), \
                mock.patch.object(subprocess, 'Popen', side_effect=AssertionError('started a process')), \
                mock.patch.object(subprocess, 'run', side_effect=AssertionError('ran a command')), \
                mock.patch.object(os, 'system', side_effect=AssertionError('ran a command')), \
                mock.patch('webbrowser.open', side_effect=AssertionError('opened a page')):
            for method, params in calls.items():
                answer = await phone.call(method, params, elevated=True)
                self.assertTrue(answer['ok'], (method, answer))
                if method != 'terminal_propose':
                    self.assertEqual(answer['result'], {'ok': True}, method)
        log = captured.getvalue()
        self.assertEqual(log.count('would open'), 8)  # the card is not an opening
        for secret in ('example.com', 'Calculator', 'ls -la', 'artifact-1', 'attempt-1', 'process-1'):
            self.assertNotIn(secret, log)  # the log stays content-free

    async def test_the_open_methods_refuse_what_pebble_refuses(self):
        phone = self.phone
        cases = [
            ('open_url', {'url': 'http://example.com/'}, 'Only public HTTPS links can be opened.'),
            ('open_url', {'url': 'https://user:pw@example.com/'}, 'Only public HTTPS links can be opened.'),
            ('open_url', {'url': 'https://' + 'a' * 3000 + '.com'}, 'Only public HTTPS links can be opened.'),
            ('open_url', {'url': 'https://127.0.0.1/'},
             'Only public HTTPS sources are allowed. Local and private networks are blocked.'),
            ('open_url', {'url': 'https://printer.local/'},
             'Only public HTTPS sources are allowed. Local and private networks are blocked.'),
            ('open_app', {'id': self.project_chat, 'app_id': ''}, 'Select an installed app.'),
            ('open_app', {'id': 'no-such-chat', 'app_id': 'com.apple.Calculator'}, 'Conversation not found.'),
            ('browser_open_tab', {'url': 'http://example.com/'}, 'Open an https address, or an http address on this Mac.'),
            ('terminal_propose', {'id': self.plain_chat, 'command': 'ls'}, 'Select a project folder first.'),
            ('terminal_propose', {'id': self.project_chat, 'command': 'ls | wc -l'},
             'Run one command at a time. Pipes, redirections and chained shell commands are blocked.'),
            ('terminal_propose', {'id': self.project_chat, 'command': 'echo $(whoami)'},
             'Command substitutions and environment overrides are blocked.'),
            ('terminal_propose', {'id': self.project_chat, 'command': ''},
             'Enter a single command shorter than 4000 characters.'),
            ('terminal_propose', {'id': self.project_chat, 'command': 'ls', 'network': 'yes'},
             'Enter a single command shorter than 4000 characters.'),
            ('open_url', {'conformance_check': True}, mock_bridge.DEFECT_TEXT),
            ('terminal_propose', {'conformance_check': True}, mock_bridge.DEFECT_TEXT),
        ]
        for method, params, words in cases:
            answer = await phone.call(method, params, elevated=True)
            self.assertEqual((answer['ok'], answer['error']), (False, words), (method, params))
            self.assertNotIn('code', answer)  # Pebble's own refusal: no bridge code

    async def test_terminal_propose_makes_a_review_card_that_the_phone_can_approve(self):
        phone, chat = self.phone, self.project_chat
        before = {a['id'] for a in self.sim.actions[chat]}
        answer = await phone.call('terminal_propose', {'id': chat, 'command': 'ls -la src', 'network': True},
                                  elevated=True)
        self.assertEqual(set(answer['result']), {'status', 'action_id', 'kind'})
        self.assertEqual((answer['result']['status'], answer['result']['kind']), ('awaiting_user_approval', 'command'))
        card = next(a for a in self.sim.actions[chat] if a['id'] == answer['result']['action_id'])
        self.assertNotIn(card['id'], before)
        self.assertEqual((card['kind'], card['status']), ('command', 'pending'))
        payload = card['payload']
        self.assertEqual((payload['command'], payload['argv'], payload['network'], payload['root']),
                         ('ls -la src', ['ls', '-la', 'src'], True, mock_bridge.PROJECT))
        self.assertTrue(payload['requires_review'])
        # Pebble's actions event, then the conversation as the phone reads it
        events = [json.loads(frame) for _, _, frame in self.bridge.buffer]
        sent = [e for e in events if e['event'] == 'actions' and e['data']['chat_id'] == chat]
        self.assertIn(card['id'], [a['id'] for a in sent[-1]['data']['actions']])
        chat_view = (await phone.call('get_chat', {'id': chat}))['result']
        self.assertIn(card['id'], [a['id'] for a in chat_view['actions']])
        # the person approves it with Face ID: the simulated result says that nothing was run
        approved = await phone.call('approve', {'id': chat, 'action_id': card['id']}, elevated=True)
        self.assertTrue(approved['ok'], approved)
        self.assertEqual(approved['result']['exit_code'], 0)
        self.assertEqual(approved['result']['command'], 'ls -la src')
        self.assertIn('Simulated: nothing was run', approved['result']['output'])
        self.assertIn('network allowed', approved['result']['isolation'])
        # and a second one can be rejected
        second = await phone.call('terminal_propose', {'id': chat, 'command': 'pwd'}, elevated=True)
        rejected = await phone.call('reject', {'id': chat, 'action_id': second['result']['action_id']})
        self.assertTrue(rejected['ok'], rejected)

    async def test_terminal_propose_waits_for_a_running_task(self):
        self.sim.active = self.project_chat
        answer = await self.phone.call('terminal_propose', {'id': self.project_chat, 'command': 'ls'}, elevated=True)
        self.assertEqual(answer['error'], 'Wait for the current task before starting a terminal command.')

    async def test_the_welcome_offers_folders_and_lists_the_nine_as_elevated(self):
        conn = mock_bridge.Conn(self.bridge, None, 2)
        record = self.bridge.registry.get(self.phone.device)
        self.bridge.authenticate(conn, record, None)
        welcome = next(json.loads(text) for text in conn.queue if json.loads(text)['t'] == 'welcome')
        self.assertIn('remote.folders', welcome['methods'])
        self.assertIn('0.6', welcome['bridge']['version'])
        for method in wire.OPEN_ON_MAC:
            self.assertIn(method, welcome['methods'])
            self.assertIn(method, welcome['elevated'])
        self.assertNotIn('remote.folders', welcome['elevated'])
        self.assertNotIn('set_workspace', welcome['elevated'])

    # -- attach_url ----------------------------------------------------------------------------------------------------

    async def test_attach_url_adds_a_source_that_the_next_message_carries(self):
        phone, chat = self.phone, self.plain_chat
        answer = await phone.call('attach_url', {'id': chat, 'url': 'https://example.com/guide?page=2#top'})
        self.assertTrue(answer['ok'], answer)
        source = answer['result']
        self.assertEqual(set(source), {'id', 'name', 'characters'})  # Pebble's add_source answer
        self.assertEqual((source['name'], source['characters']), ('https://example.com/guide?page=2#top', 2400))
        self.assertEqual([s['id'] for s in self.sim.sources[chat]], [source['id']])
        sent = await phone.call('send', {'id': chat, 'text': 'Summarise that page', 'source_ids': [source['id']]})
        self.assertTrue(sent['ok'], sent)
        chat_view = (await phone.call('get_chat', {'id': chat}))['result']
        mine = next(m for m in chat_view['messages'] if m['id'] == sent['result']['message_id'])
        self.assertEqual([(a['id'], a['kind']) for a in mine['attachments']], [(source['id'], 'url')])
        self.assertNotIn(chat, self.sim.sources)  # the sources went with the message
        await self.wait_idle()

    async def wait_idle(self):
        for _ in range(500):
            if not self.sim.active and not self.sim.pending_launches:
                return
            await asyncio.sleep(0.01)
        self.fail('the simulated run did not finish')

    async def test_attach_url_refuses_what_pebble_refuses_in_pebbles_order(self):
        phone, chat = self.phone, self.plain_chat
        public = 'Enter a public https:// URL without credentials or a custom port.'
        for url, words in (('http://example.com/', public), ('https://user:pw@example.com/', public),
                           ('https://example.com:8443/', public), ('https://example.com/a b', public),
                           ('https:///nohost', public), ('ftp://example.com/', public), ('example.com', public),
                           ('https://' + 'a' * 3000, 'Use a public URL shorter than 3,000 characters.'),
                           (5, 'Use a public URL shorter than 3,000 characters.'),
                           ('https://192.168.1.20/', 'Only public HTTPS sources are allowed. Local and private '
                                                    'networks are blocked.'),
                           ('https://localhost/x', 'Only public HTTPS sources are allowed. Local and private '
                                                   'networks are blocked.')):
            answer = await phone.call('attach_url', {'id': chat, 'url': url})
            self.assertEqual((answer['ok'], answer['error']), (False, words), url if isinstance(url, int) else url[:40])
            self.assertNotIn('code', answer)
        # the conversation is checked before the address, the web switch before both
        self.assertEqual((await phone.call('attach_url', {'id': 'nope', 'url': 'https://example.com/'}))['error'],
                         'Conversation not found.')
        self.sim.settings['permissions']['tools']['web'] = False
        self.assertEqual((await phone.call('attach_url', {'id': 'nope', 'url': 'http://x'}))['error'],
                         'Web access is disabled in Permissions.')
        self.sim.settings['permissions']['tools']['web'] = True
        for number in range(10):
            self.assertTrue((await phone.call('attach_url', {'id': chat, 'url': 'https://example.com/%d' % number}))['ok'])
        eleventh = await phone.call('attach_url', {'id': chat, 'url': 'https://example.com/11'})
        self.assertEqual(eleventh['error'], 'Use up to ten sources per message.')
        removed = await phone.call('remove_source', {'id': chat, 'source_id': self.sim.sources[chat][0]['id']})
        self.assertTrue(removed['ok'])
        self.assertTrue((await phone.call('attach_url', {'id': chat, 'url': 'https://example.com/12'}))['ok'])

    async def test_attach_url_needs_the_unlock_and_an_idem(self):
        phone, chat = self.phone, self.plain_chat
        phone.lock()
        answer = await phone.call('attach_url', {'id': chat, 'url': 'https://example.com/'})
        self.assertEqual(answer['code'], 'unlock_required')
        phone.unlock()
        answer = await phone.call('attach_url', {'id': chat, 'url': 'https://example.com/'}, idem=False)
        self.assertEqual(answer['code'], 'bad_request')  # it adds something: v0.3 item 4


# =====================================================================================================================
# End to end: the mock on an ephemeral port, conformance against it
# =====================================================================================================================

# =====================================================================================================================
# Proposal v0.6: a new folder, made from the phone
# =====================================================================================================================

class FolderNameTests(unittest.TestCase):
    """The name of a new folder: trimmed, then 1 to 255 bytes of UTF-8, no / or :, no control characters, not . or ..,
    no leading dot (remote_wire.trim_folder_name and folder_name_problem, shared by the mock and the checker)."""

    def test_the_trim_cuts_separators_tabs_and_line_breaks(self):
        for raw, trimmed in (('  app ', 'app'), ('\t\napp\r\n', 'app'), (' app ', 'app'),
                             (' app ', 'app'), ('\x85app', 'app'), ('\x0bapp\x0c', 'app'), ('a b', 'a b'),
                             ('   ', ''), ('', ''), ('a\nb', 'a\nb'), ('　app　', 'app')):
            self.assertEqual(wire.trim_folder_name(raw), trimmed, repr(raw))
        self.assertEqual(wire.trim_folder_name('​app'), '​app')  # a zero-width space is a format character

    def test_names_that_are_taken(self):
        for name in ('app', 'my app', 'v1.2', 'a.b', 'name.', 'café', '\U0001f4c1 notes', '项目', '-dash',
                     '_under', 'x' * 255, 'é' * 127, '\U0001f4c1' * 63, 'a' * 200 + 'é' * 27,
                     '‍\U0001f468‍\U0001f469'):
            self.assertIsNone(wire.folder_name_problem(name), repr(name))

    def test_names_that_are_not(self):
        for name, problem in (('', 'empty'), ('x' * 256, 'long'), ('é' * 128, 'long'), ('\U0001f4c1' * 64, 'long'),
                              ('/', 'separator'), ('a/b', 'separator'), ('a:b', 'separator'), (':', 'separator'),
                              ('a/b\x00', 'separator'), ('a\x00b', 'control'), ('a\nb', 'control'), ('a\tb', 'control'),
                              ('\x7f', 'control'), ('a\x85b', 'control'), ('a\x9fb', 'control'), ('.', 'dot'),
                              ('..', 'dot'), ('.git', 'dot'), ('.hidden', 'dot'), ('\ud800', 'encoding')):
            self.assertEqual(wire.folder_name_problem(name), problem, repr(name))

    def test_every_problem_has_words_without_a_banned_word(self):
        problems = {'empty', 'encoding', 'long', 'separator', 'control', 'dot', 'private'}
        self.assertEqual(set(mock_bridge.NAME_WORDS), problems)
        for words in [*mock_bridge.NAME_WORDS.values(), *(mock_bridge.FOLDER_WORDS[k] for k in
                                                            ('exists', 'not_writable', 'not_made'))]:
            self.assertIsNone(BANNED_WORDS.search(words), words)
            self.assertNotIn('/Users', words)
        self.assertEqual(mock_bridge.FOLDER_WORDS['exists'], 'A folder with that name is already there.')  # the proposal's


class FolderCreateTests(unittest.TestCase):
    """`Folders.create`: one empty folder, made for real in a test tree, and every refusal that leaves the tree as it was."""

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = make_tree(os.path.join(self.folder.name, 'home'))
        self.folders = mock_bridge.Folders(self.root, extra_protected=[os.path.join(self.root, 'mock-state')])

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def everything(self):
        """Every folder and file in the tree and in the temporary folder above it: what a refusal must leave alone."""
        found = set()
        for here, folders, files in os.walk(os.path.dirname(self.root)):
            found.update(os.path.join(here, name) for name in (*folders, *files))
        return found

    def refused(self, parent, name):
        before = self.everything()
        with self.assertRaises(mock_bridge.FolderRefused) as caught:
            self.folders.create(parent, name)
        self.assertEqual(self.everything(), before, 'a refusal changed the disk')
        return caught.exception

    def test_it_makes_one_empty_folder_and_answers_its_entry(self):
        before = self.everything()
        made = self.folders.create(self.path('Projects'), 'new-app')
        self.assertEqual(made, {'path': self.path('Projects', 'new-app'), 'name': 'new-app', 'is_project': False})
        self.assertIs(type(made['is_project']), bool)
        self.assertEqual(self.everything() - before, {made['path']})  # one folder, no intermediate one, nothing inside
        self.assertTrue(os.path.isdir(made['path']) and not os.path.islink(made['path']))
        self.assertEqual(os.listdir(made['path']), [])
        listed = [row for row in self.folders.listing(self.path('Projects'))['folders'] if row['name'] == 'new-app']
        self.assertEqual(listed, [made])  # exactly as remote.folders gives an entry
        self.assertTrue(self.folders.listable(made['path']))  # so it can be connected as a new folder

    def test_the_home_folder_is_a_parent_and_a_trailing_slash_means_the_same(self):
        self.assertEqual(self.folders.create(self.root, 'top')['path'], self.path('top'))
        self.assertEqual(self.folders.create(self.path('Projects') + '/', 'two')['path'], self.path('Projects', 'two'))
        self.assertEqual(self.folders.create(self.root + '/', 'three')['path'], self.path('three'))

    def test_a_made_folder_can_hold_another(self):
        outer = self.folders.create(self.root, 'outer')
        inner = self.folders.create(outer['path'], 'inner')
        self.assertEqual(self.folders.listing(outer['path'])['folders'], [inner])
        self.assertEqual(self.folders.listing(outer['path'])['parent'], self.root)

    def test_the_name_is_trimmed(self):
        made = self.folders.create(self.root, '  spaced name \n')
        self.assertEqual((made['name'], made['path']), ('spaced name', self.path('spaced name')))
        self.assertTrue(os.path.isdir(self.path('spaced name')))

    def test_names_in_any_language_and_the_longest_one_are_kept(self):
        for name in ('café', '\U0001f4c1 notes', '项目', 'v1.2', 'x' * 255):
            self.assertEqual(self.folders.create(self.root, name)['name'], name)
            self.assertTrue(os.path.isdir(self.path(name)))

    def test_a_name_outside_the_rules_is_bad_request_in_words_and_makes_nothing(self):
        parent = self.path('Projects')
        for name, problem in (('', 'empty'), ('   ', 'empty'), ('.', 'dot'), ('..', 'dot'), ('.hidden', 'dot'),
                              ('a/b', 'separator'), ('a:b', 'separator'), ('a\nb', 'control'), ('a\x07b', 'control'),
                              ('x' * 256, 'long'), ('é' * 128, 'long'), ('\ud800', 'encoding')):
            with self.subTest(name=name[:8]):
                error = self.refused(parent, name)
                self.assertEqual((error.code, error.words), ('bad_request', mock_bridge.NAME_WORDS[problem]))
        for parent_value, name in ((parent, 5), (parent, None), (parent, ['a']), (5, 'x'), (None, 'x'), (['a'], 'x')):
            error = self.refused(parent_value, name)  # not strings: the generic words
            self.assertEqual((error.code, error.words), ('bad_request', mock_bridge.ERRORS['bad_request']))

    def test_a_name_the_listing_would_hide_is_refused_too(self):
        """The mock's own addition: a folder `remote.folders` would not show could never be shown or connected."""
        for parent, name in ((self.root, 'secrets'), (self.root, 'my.key'), (self.root, 'prod.env'),
                             (self.root, 'credentials'), (self.root, 'id_rsa'), (self.root, 'x.tfstate'),
                             (self.root, 'PebbleBackups'), (self.root, 'mock-state'), (self.path('Documents'), 'Pebble'),
                             (self.path('Work'), 'kubeconfig')):
            with self.subTest(name=name):
                error = self.refused(parent, name)
                self.assertEqual((error.code, error.words), ('bad_request', mock_bridge.NAME_WORDS['private']))

    def test_a_parent_outside_the_rules_is_not_allowed(self):
        name = 'pebble-remote-test-new'
        for parent in ('/', '/etc', '/usr', os.path.dirname(self.root), self.root + '/..', self.root + '//Projects',
                       self.path('Projects', '..', '..'), self.path('usrlink'), self.path('usrlink', 'bin'),
                       self.path('ProjectsLink'), self.path('ProjectsLink', 'app'), self.path('.ssh'),
                       self.path('.hidden'), self.path('.hidden', 'inner'), self.path('PebbleBackups'),
                       self.path('Documents', 'Pebble'), self.path('secrets'), self.path('mock-state'),
                       self.path('.claude-other'), self.path('.nowhere')):
            with self.subTest(parent=parent.replace(self.root, '~')):
                error = self.refused(parent, name)
                self.assertEqual(error.code, 'not_allowed')
                self.assertIn(error.words, (mock_bridge.FOLDER_WORDS['outside'], mock_bridge.FOLDER_WORDS['private']))
                self.assertFalse(os.path.exists(os.path.join('/usr', name)))
                self.assertFalse(os.path.exists(os.path.join(os.path.dirname(self.root), name)))

    def test_a_parent_that_is_not_there_or_is_a_file_gets_words_and_no_code(self):
        for parent in (self.path('nope'), self.path('Projects', 'nope', 'deeper'), self.path('notes.txt')):
            error = self.refused(parent, 'x')
            self.assertEqual((error.code, error.words), (None, mock_bridge.FOLDER_WORDS['missing']))
        self.assertFalse(os.path.exists(self.path('nope')))  # no intermediate folder either

    def test_a_name_already_there_gets_the_proposals_words_and_no_code(self):
        names = ['app', 'lib', 'notes.txt']  # a folder, another folder, and a file
        if os.path.exists(self.path('ARCHIVE')):  # a case-insensitive disk, as the Mac's is by default
            names.append('ARCHIVE')
        for name in names:
            with self.subTest(name=name):
                parent = self.path('Projects') if name in ('app', 'lib') else self.root
                error = self.refused(parent, name)
                self.assertEqual((error.code, error.words), (None, 'A folder with that name is already there.'))
        self.assertTrue(os.path.isdir(self.path('Projects', 'app', '.git')))  # the folder that was there is untouched

    def test_a_parent_that_cannot_be_written_gets_words(self):
        if os.geteuid() == 0:
            self.skipTest('root can write anywhere')
        locked = self.path('Archive')
        os.chmod(locked, 0o555)
        self.addCleanup(os.chmod, locked, 0o755)
        error = self.refused(locked, 'x')
        self.assertEqual((error.code, error.words), (None, mock_bridge.FOLDER_WORDS['not_writable']))

    def test_a_write_that_fails_for_another_reason_gets_words(self):
        import errno
        for target in ('mkdir', 'open'):
            with self.subTest(target), mock.patch.object(os, target, side_effect=OSError(errno.ENOSPC, 'no room')):
                error = self.refused(self.path('Projects'), 'x')
                self.assertEqual((error.code, error.words), (None, mock_bridge.FOLDER_WORDS['not_made']))

    def test_the_folder_is_made_inside_the_folder_that_was_checked(self):
        """A parent swapped for a link between the check and the write is not followed (O_NOFOLLOW on the folder)."""
        with mock.patch.object(self.folders, 'locate', return_value=self.path('ProjectsLink')):
            error = self.refused(self.path('Work'), 'swapped')
        self.assertEqual(error.words, mock_bridge.FOLDER_WORDS['not_made'])
        self.assertFalse(os.path.exists(self.path('Projects', 'swapped')))


class V06BridgeTests(unittest.IsolatedAsyncioTestCase):
    """The bridge's rules for proposal v0.6, in this process: who may make a folder, and that a folder this device made
    in the last ten minutes connects with the unlock alone."""

    async def asyncSetUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = make_tree(os.path.join(self.folder.name, 'home'))
        registry = mock_bridge.Registry(os.path.join(self.folder.name, 'devices.json'))
        self.bridge = mock_bridge.Bridge(StubIdentity(), registry, name='Test Mac', speed=50, folders_root=self.root,
                                         state_dir=os.path.join(self.root, 'mock-state'))
        self.sim = self.bridge.sim
        self.phone = InProcessPhone(self.bridge)
        self.phone.unlock()
        self.plain_chat = next(c for c, row in self.sim.chats.items() if row['workspace'] is None)

    async def asyncTearDown(self):
        for task in list(self.sim.tasks.values()):
            task.cancel()
        self.folder.cleanup()

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def workspace_of(self, chat_id):
        return self.sim.chats[chat_id]['workspace']

    async def make(self, name='fresh', parent=None, phone=None):
        answer = await (phone or self.phone).call('remote.folder_create', {'parent': parent or self.path('Projects'),
                                                                           'name': name}, elevated=True)
        self.assertTrue(answer['ok'], answer)
        return answer['result']['path']

    # -- remote.folder_create ------------------------------------------------------------------------------------------

    async def test_a_new_folder_needs_a_proof_and_the_proof_unlocks(self):
        phone = self.phone
        params = {'parent': self.path('Projects'), 'name': 'fresh'}
        for state in ('locked', 'unlocked'):  # elevated: proof_required, whether or not the phone is unlocked
            phone.lock() if state == 'locked' else phone.unlock()
            answer = await phone.call('remote.folder_create', params)
            self.assertEqual((answer['ok'], answer['code']), (False, 'proof_required'), state)
            self.assertEqual(answer['error'], mock_bridge.ERRORS['proof_required'])
        self.assertFalse(os.path.exists(self.path('Projects', 'fresh')))
        phone.lock()  # the proof itself unlocks the phone (C1)
        answer = await phone.call('remote.folder_create', params, elevated=True)
        self.assertTrue(answer['ok'], answer)
        self.assertEqual(answer['result'], {'path': self.path('Projects', 'fresh'), 'name': 'fresh', 'is_project': False})
        self.assertTrue(os.path.isdir(self.path('Projects', 'fresh')))
        self.assertTrue(self.bridge.is_unlocked(phone.device))

    async def test_it_needs_an_idem_and_works_while_the_simulated_pebble_is_stopped(self):
        answer = await self.phone.call('remote.folder_create', {'parent': self.root, 'name': 'x'}, idem=False)
        self.assertEqual((answer['ok'], answer['code']), (False, 'bad_request'))  # not a read: a retry key goes on it
        self.assertFalse(os.path.exists(self.path('x')))
        self.sim.running = False  # the bridge's own, like the listing
        await self.make('while-stopped', parent=self.root)
        self.assertTrue(os.path.isdir(self.path('while-stopped')))

    async def test_refusals_over_the_bridge_and_their_codes(self):
        phone = self.phone
        cases = [({'parent': self.path('Projects'), 'name': '.hidden'}, 'bad_request', mock_bridge.NAME_WORDS['dot']),
                 ({'parent': self.path('Projects'), 'name': 'a/b'}, 'bad_request', mock_bridge.NAME_WORDS['separator']),
                 ({'parent': self.path('Projects'), 'name': ''}, 'bad_request', mock_bridge.NAME_WORDS['empty']),
                 ({'parent': '/usr', 'name': 'x'}, 'not_allowed', mock_bridge.FOLDER_WORDS['outside']),
                 ({'parent': self.path('.ssh'), 'name': 'x'}, 'not_allowed', mock_bridge.FOLDER_WORDS['private']),
                 ({'parent': self.path('Projects', 'nope'), 'name': 'x'}, None, mock_bridge.FOLDER_WORDS['missing']),
                 ({'parent': self.path('Projects'), 'name': 'app'}, None, mock_bridge.FOLDER_WORDS['exists']),
                 ({'parent': self.path('Projects')}, 'bad_request', mock_bridge.ERRORS['bad_request'])]
        for params, code, words in cases:
            answer = await phone.call('remote.folder_create', params, elevated=True)
            self.assertFalse(answer['ok'], params)
            self.assertEqual(answer.get('code'), code, answer)
            self.assertEqual(answer['error'], words)
            self.assertNotIn(self.root, answer['error'])  # the words say nothing about the Mac's paths

    async def test_the_log_is_content_free(self):
        mock_bridge.QUIET = False
        self.addCleanup(setattr, mock_bridge, 'QUIET', True)
        captured = io.StringIO()
        with contextlib.redirect_stderr(captured):
            await self.make('secret-project-name')
            await self.phone.call('remote.folder_create', {'parent': self.path('Projects'), 'name': 'secret-project-name'},
                                  elevated=True)  # the second one is refused
            await self.phone.call('remote.folder_create', {'parent': self.path('.ssh'), 'name': 'x'}, elevated=True)
        log = captured.getvalue()
        self.assertIn('remote.folder_create', log)
        self.assertEqual(log.count('made a folder'), 1)
        for word in ('secret-project-name', 'Projects', '.ssh', self.root, os.path.basename(self.root)):
            self.assertNotIn(word, log)

    async def test_two_phones_making_the_same_name_make_it_once(self):
        other = InProcessPhone(self.bridge)
        other.unlock()
        params = {'parent': self.path('Projects'), 'name': 'both'}
        first, second = await asyncio.gather(self.phone.call('remote.folder_create', params, elevated=True),
                                             other.call('remote.folder_create', params, elevated=True))
        self.assertEqual(sorted([first['ok'], second['ok']]), [False, True])
        loser = first if not first['ok'] else second
        self.assertEqual((loser.get('code'), loser['error']), (None, mock_bridge.FOLDER_WORDS['exists']))
        winner = self.phone if first['ok'] else other
        self.assertEqual(list(self.bridge.made), [winner.device])  # the one that lost made nothing, so it owns nothing

    # -- the ten minutes ----------------------------------------------------------------------------------------------

    async def test_a_folder_this_device_made_connects_with_the_unlock_alone(self):
        phone, chat = self.phone, self.plain_chat
        one, two = await self.make('one'), await self.make('two')  # each call alone makes its folder a project in use
        self.assertTrue(self.bridge.made_by(phone.device, one) and self.bridge.made_by(phone.device, two))
        answer = await phone.call('set_workspace', {'id': chat, 'path': one})  # a plain call: no proof
        self.assertTrue(answer['ok'], answer)
        self.assertEqual((answer['result']['workspace'], self.workspace_of(chat)), (one, one))
        before = len(self.sim.chats)
        answer = await phone.call('new_chat', {'workspace': two})
        self.assertTrue(answer['ok'], answer)
        self.assertEqual(answer['result']['workspace'], two)
        self.assertEqual(len(self.sim.chats), before + 1)
        # an elevated call works too, as it always did
        self.assertTrue((await phone.call('set_workspace', {'id': chat, 'path': None}))['ok'])
        self.assertTrue((await phone.call('set_workspace', {'id': chat, 'path': one}, elevated=True))['ok'])

    async def test_it_is_exactly_that_path_for_that_device_for_ten_minutes(self):
        phone, chat = self.phone, self.plain_chat
        other = InProcessPhone(self.bridge)
        other.unlock()
        folder = await self.make()
        lib = self.path('Projects', 'lib')  # a listed folder nobody made
        for path in (lib, self.path('Projects'), folder + '/', folder + '/inner', folder.upper(), self.root):
            for method, params in (('set_workspace', {'id': chat, 'path': path}), ('new_chat', {'workspace': path})):
                answer = await phone.call(method, params)
                self.assertEqual((answer['ok'], answer['code']), (False, 'proof_required'), (method, path))
        for method, params in (('set_workspace', {'id': chat, 'path': folder}), ('new_chat', {'workspace': folder})):
            answer = await other.call(method, params)  # another device did not make it
            self.assertEqual((answer['ok'], answer['code']), (False, 'proof_required'), method)
        self.assertIsNone(self.workspace_of(chat))
        # just inside the ten minutes it still holds
        self.bridge.made[phone.device][folder] = time.monotonic() - (mock_bridge.MADE_FOLDER_SECONDS - 5)
        self.assertTrue((await phone.call('new_chat', {'workspace': folder}))['ok'])

    async def test_ten_minutes_after_the_make_a_new_folder_needs_its_proof_again(self):
        phone, chat = self.phone, self.plain_chat
        folder = await self.make()
        self.bridge.made[phone.device][folder] -= mock_bridge.MADE_FOLDER_SECONDS + 1
        for method, params in (('set_workspace', {'id': chat, 'path': folder}), ('new_chat', {'workspace': folder})):
            answer = await phone.call(method, params)
            self.assertEqual((answer['ok'], answer['code']), (False, 'proof_required'), method)
        self.assertTrue((await phone.call('set_workspace', {'id': chat, 'path': folder}, elevated=True))['ok'])

    async def test_a_locked_phone_still_needs_the_unlock(self):
        phone, chat = self.phone, self.plain_chat
        folder = await self.make()
        phone.lock()  # S-05, or the unlock lapsing: the person unlocks again, and the memory still holds
        answer = await phone.call('set_workspace', {'id': chat, 'path': folder})
        self.assertEqual((answer['ok'], answer['code']), (False, 'unlock_required'))
        phone.unlock()
        self.assertTrue((await phone.call('set_workspace', {'id': chat, 'path': folder}))['ok'])

    async def test_a_made_folder_that_is_not_a_listed_folder_any_more_is_refused(self):
        phone, chat = self.phone, self.plain_chat
        folder = await self.make()
        os.rmdir(folder)
        answer = await phone.call('set_workspace', {'id': chat, 'path': folder})
        self.assertEqual((answer['ok'], answer['code'], answer['error']),
                         (False, 'not_allowed', mock_bridge.WORKSPACE_REFUSED))
        os.symlink(self.path('Work'), folder)  # a link in its place: never connected
        answer = await phone.call('new_chat', {'workspace': folder})
        self.assertEqual((answer['ok'], answer['code']), (False, 'not_allowed'))
        self.assertIsNone(self.workspace_of(chat))

    async def test_what_a_device_made_is_forgotten_when_it_is_removed(self):
        phone = self.phone
        await self.make()
        self.assertIn(phone.device, self.bridge.made)
        answer = await phone.call('remote.revoke_device', {'device_id': phone.device})
        self.assertTrue(answer['ok'], answer)
        self.assertNotIn(phone.device, self.bridge.made)

    def test_at_most_64_folders_are_remembered_for_a_device_and_the_old_are_dropped(self):
        bridge, device = self.bridge, 'd-many'
        for number in range(70):
            bridge.remember_made(device, '/made/%d' % number)
        self.assertEqual(len(bridge.made[device]), mock_bridge.MADE_FOLDERS_KEPT)
        self.assertFalse(bridge.made_by(device, '/made/0'))
        self.assertTrue(bridge.made_by(device, '/made/6') and bridge.made_by(device, '/made/69'))
        bridge.made[device]['/made/69'] -= mock_bridge.MADE_FOLDER_SECONDS + 1  # old: forgotten by the next one
        bridge.remember_made(device, '/made/new')
        self.assertNotIn('/made/69', bridge.made[device])
        self.assertFalse(bridge.made_by(device, 7))  # not a path
        self.assertFalse(bridge.made_by('nobody', '/made/new'))

    async def test_the_welcome_offers_the_method_as_elevated(self):
        conn = mock_bridge.Conn(self.bridge, None, 2)
        self.bridge.authenticate(conn, self.bridge.registry.get(self.phone.device), None)
        welcome = next(json.loads(text) for text in conn.queue if json.loads(text)['t'] == 'welcome')
        self.assertIn('remote.folder_create', welcome['methods'])
        self.assertIn('remote.folder_create', welcome['elevated'])
        self.assertIn('0.6', welcome['bridge']['version'])
        self.assertNotIn('set_workspace', welcome['elevated'])  # still elevated for a new folder only


class EndToEndTests(unittest.TestCase):
    def start_mock(self, state, *extra):
        """The mock on an ephemeral port. X-1's auto confirmation takes 0.05 s here instead of about 1.5 s, unless the
        test passes its own --pair-confirm-delay (after this one, so it wins)."""
        process = subprocess.Popen([sys.executable, '-I', os.path.join(HERE, 'mock_bridge.py'), '--host', '127.0.0.1',
                                    '--port', '0', '--state-dir', state, '--quiet', '--pair-confirm-delay', '0.05',
                                    *extra],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, stdin=subprocess.PIPE)
        lines = {}
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            line = process.stdout.readline()
            if not line:
                break
            key, _, value = line.strip().partition('=')
            lines.setdefault(key, value)
            if key == 'READY':
                return process, lines
        process.kill()
        self.fail('the mock did not start: ' + process.stderr.read()[-500:])

    def stop_mock(self, process):
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()
        process.stderr.close()
        process.stdin.close()

    def run_conformance(self, link, folder, *extra):
        report = os.path.join(folder, 'report.json')
        done = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'conformance.py'), '--link', link,
                               '--json', report, *extra], capture_output=True, text=True, timeout=240)
        with open(report) as handle:
            return done, json.load(handle)['results']

    async def paired(self, link, label='P'):
        import conformance
        checker = conformance.Checker(link, timeout=10)
        checker.endpoint = checker.link['endpoints'][0]
        peer = await checker.peer(label)
        paired, welcome = await peer.pair(checker.link['code'], checker.phone.device_key, checker.phone.approve_key)
        self.assertEqual(paired['t'], 'paired')
        checker.phone.device_id, checker.epoch = paired['device_id'], welcome['epoch']
        return checker, peer

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_conformance_passes_against_the_mock(self):
        import conformance
        with tempfile.TemporaryDirectory() as folder:
            state = os.path.join(folder, 'state')
            tree = make_tree(os.path.join(folder, 'home'))  # remote.folders lists this, never the real home folder
            process, lines = self.start_mock(state, '--print-pairing', '--speed', '4', '--folders-root', tree,
                                             '--pair-confirm-delay', '1.5')  # the default: the timing row needs it
            try:
                link = lines['PAIRING_LINK']
                self.assertTrue(link.startswith('pebble-remote://pair?v=1&bid='))
                self.assertEqual(wire.parse_pairing_link(link)['endpoints'], [('127.0.0.1', int(lines['PORT']))])
                done, results = self.run_conformance(link, folder)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assertGreaterEqual(len(results), 30)
                self.assertEqual([r['name'] for r in results if r['ok'] is False], [])
                self.assertEqual(sorted(r['name'] for r in results if r['ok'] is None),
                                 ['C6: at most 10 handshakes a minute from one address',
                                  'C6: the Bonjour instance is named by the bridge id'])  # LAN-only and opt-in
                passed = {r['name'] for r in results if r['ok'] is True}  # every row of the later proposals ran, and passed
                checker = conformance.Checker
                self.assertLessEqual({checker.V05_LOCKED, *checker.V05_ROWS, *checker.V06_ROWS, *checker.X1_ROWS,
                                      checker.S05_LOCK, checker.S05_LAST}, passed)
                # the 37 rows of v0.3 (35 pass, 2 skip), v0.5's 8, v0.6's 3, X-1's 2 and S-05's 2
                self.assertEqual(len(results), 37 + 8 + 3 + 2 + 2)
                self.assertEqual([name for name in os.listdir(tree) if name.startswith('pebble-remote-')], [])
                # a new pairing link on SIGUSR1, with a new code and the same pin
                process.send_signal(signal.SIGUSR1)
                fresh = None
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline and fresh is None:
                    line = process.stdout.readline().strip()
                    if line.startswith('PAIRING_LINK='):
                        fresh = wire.parse_pairing_link(line.partition('=')[2])
                self.assertIsNotNone(fresh)
                self.assertNotEqual(fresh['code'], wire.parse_pairing_link(link)['code'])
                self.assertEqual(fresh['pin'], lines['PIN'])
            finally:
                self.stop_mock(process)
            with open(os.path.join(state, 'devices.json')) as handle:
                devices = json.load(handle)
            self.assertEqual(devices['devices'], {})          # conformance removed its own device
            self.assertEqual(len(devices['revoked']), 1)
            self.assertEqual(stat.S_IMODE(os.stat(os.path.join(state, 'devices.json')).st_mode), 0o600)
            again, lines_again = self.start_mock(state)       # a restart keeps the key, so the pin
            try:
                self.assertEqual(lines_again['PIN'], lines['PIN'])
                self.assertEqual(lines_again['BID'], lines['BID'])
                self.assertNotIn('PAIRING_LINK', lines_again)  # pairing stays off unless asked for
            finally:
                self.stop_mock(again)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_conformance_fails_a_bridge_on_v02_proofs(self):
        """The checker discriminates: a bridge that still verifies v0.2's T_proof fails the v0.3 rows."""
        with tempfile.TemporaryDirectory() as folder:
            process, lines = self.start_mock(os.path.join(folder, 'state'), '--print-pairing', '--speed', '4',
                                             '--proof-version', '2', '--pair-confirm-delay', '1.2')
            try:
                done, results = self.run_conformance(lines['PAIRING_LINK'], folder)
            finally:
                self.stop_mock(process)
        self.assertEqual(done.returncode, 1)
        failed = [r['name'] for r in results if r['ok'] is False]
        self.assertIn('a bad proof gets bad_proof (v0.3 T_proof: nonce, idem)', failed)
        self.assertIn('C1: remote.unlock with a proof unlocks; then acting works', failed)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_approve_and_p1_calls_over_the_wire(self):
        import base64
        import uuid

        async def scenario(link):
            checker, peer = await self.paired(link)
            try:
                state = (await peer.request('state'))['result']  # reads need no unlock (C1)
                cid = next(c['id'] for c in state['chats'] if c['title'] == 'Tidy the test suite')
                tail = (await peer.request('remote.chat_tail', {'id': cid, 'limit': 1}))['result']
                self.assertEqual((len(tail['messages']), tail['has_older']), (1, True))
                full = (await peer.request('get_chat', {'id': cid}))['result']
                before = await peer.request('remote.chat_before', {'id': cid, 'before': full['messages'][-1]['id'],
                                                                   'limit': 5})
                self.assertEqual(before['result'], {'messages': full['messages'][:-1], 'has_older': False})
                card = next(a for a in tail['actions'] if a['status'] == 'pending')
                self.assertEqual(card['payload']['command'], 'npm test')
                res = await peer.exchange(peer.elevated_frame('approve', {'id': cid, 'action_id': card['id']}))
                self.assertTrue(res['ok'], res)
                self.assertEqual(res['result']['exit_code'], 0)
                done = await peer.wait(lambda f: f.get('t') == 'evt' and f.get('event') == 'idle' and
                                       f['data'].get('chat_id') == cid and len([
                                           g for g in peer.frames if g.get('event') == 'run' and
                                           g['data'].get('state') == 'completed' and g['data'].get('chat_id') == cid]),
                                       10)
                self.assertIsNotNone(done, 'the run did not continue after the approval')
                again = await peer.exchange(peer.elevated_frame('approve', {'id': cid, 'action_id': card['id']}))
                self.assertEqual(again['error'], 'This action is no longer awaiting approval.')
                self.assertNotIn('code', again)  # Pebble's own refusal: no bridge code
                # the approval's proof unlocked the device (C1); keep awake needs no proof, on battery too (R3)
                off = await peer.act('remote.keep_awake', {'on': False})
                self.assertEqual(off['result'], {'keep_awake': False})
                mac = await peer.wait(lambda f: f.get('t') == 'evt' and f.get('event') == 'remote.mac', 5)
                self.assertEqual(mac[1]['data']['keep_awake'], False)
                # Recently deleted: trash, the list, Pebble's own refusal code, and the elevated purge
                trash = await peer.act('storage_trash_chat', {'chat_id': cid})
                self.assertEqual(trash['result']['trashed'], cid)
                listed = (await peer.request('state'))['result']['chats']
                self.assertNotIn(cid, [c['id'] for c in listed])
                summary = (await peer.request('storage_summary'))['result']
                self.assertEqual([r['chat_id'] for r in summary['recently_deleted']], [cid])
                refused = await peer.act('send', {'id': cid, 'text': 'hello'})
                self.assertEqual(refused['code'], 'trashed_conversation')
                plain = await peer.act('storage_purge_chat', {'chat_id': cid, 'confirm': True})
                self.assertEqual(plain['code'], 'proof_required')
                purged = await peer.exchange(peer.elevated_frame('storage_purge_chat',
                                                                 {'chat_id': cid, 'confirm': True}))
                self.assertEqual(purged['result'], {'deleted': cid})
                # a photo in two pieces (A's 72,000-byte pieces), then a new task with it
                other = next(c['id'] for c in listed if c['title'] == 'Weekly numbers')
                photo = b'\xff\xd8\xff\xe0' + os.urandom(100000)
                first = await peer.act('attach_bytes', {'id': other, 'name': 'photo.jpg', 'offset': 0, 'final': False,
                                                        'data_base64': base64.b64encode(photo[:72000]).decode()})
                second = await peer.act('attach_bytes', {'id': other, 'name': 'photo.jpg', 'offset': 72000,
                                                         'final': True, 'upload': first['result']['upload'],
                                                         'data_base64': base64.b64encode(photo[72000:]).decode()})
                attachment = second['result']
                self.assertEqual((attachment['kind'], attachment['bytes']), ('image', len(photo)))
                sent = await peer.act('send', {'id': other, 'text': 'What is in this photo?',
                                               'source_ids': [attachment['id']]})
                self.assertTrue(sent['ok'], sent)
                chat = (await peer.request('get_chat', {'id': other}))['result']
                mine = next(m for m in chat['messages'] if m['id'] == sent['result']['message_id'])
                self.assertEqual([a['id'] for a in mine['attachments']], [attachment['id']])
                # a schedule: preview (a read), then create with Face ID (work without the person)
                schedule = {'kind': 'daily', 'time': '08:00', 'timezone': 'Europe/London'}
                preview = await peer.request('job_preview', {'id': other, 'schedule': schedule, 'limits': {}})
                job = await peer.exchange(peer.elevated_frame('job_create', {
                    'id': other, 'name': 'Morning summary', 'task': 'Summarise the orders', 'schedule': schedule,
                    'monitor': False, 'limits': {}, 'config_fingerprint': preview['result']['config_fingerprint']}))
                self.assertEqual(job['result']['state'], 'active')
                jobs = (await peer.request('job_list', {'id': other}))['result']['jobs']
                self.assertIn(job['result']['id'], [j['id'] for j in jobs])
                toolbox = (await peer.act('toolbox_remove', {'name': 'csv_column_totals'}))['result']
                self.assertEqual([r['name'] for r in toolbox['removed']], ['csv_column_totals'])
                back = (await peer.act('toolbox_undo_remove', {'name': 'csv_column_totals'}))['result']
                self.assertEqual([t['name'] for t in back['tools']], ['csv_column_totals'])
            finally:
                await peer.close()

        with tempfile.TemporaryDirectory() as folder:
            process, lines = self.start_mock(os.path.join(folder, 'state'), '--print-pairing', '--speed', '8',
                                             '--battery')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK']))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_unlock_lapses_screen_refusal_and_handshake_limit(self):
        import conformance

        async def scenario(link):
            checker, peer = await self.paired(link)  # handshake 1 from 127.0.0.1
            try:
                self.assertEqual((await peer.act('new_chat', {}))['code'], 'unlock_required')
                unlocked = await peer.exchange(peer.elevated_frame('remote.unlock', {}))
                self.assertEqual(unlocked['result']['unlock_seconds'], 1)
                shot = await peer.request('remote.screenshot', {'display': None})
                self.assertFalse(shot['ok'])
                self.assertIn('Screen Recording', shot['error'])
                self.assertNotIn('code', shot)  # the Mac's refusal in words, not a bridge code
                self.assertTrue((await peer.act('new_chat', {}))['ok'])
                await asyncio.sleep(1.3)
                self.assertEqual((await peer.act('new_chat', {}))['code'], 'unlock_required')  # the window lapsed
            finally:
                await peer.close()
            for number in range(2, 11):  # handshakes 2 to 10 are fine
                extra = conformance.Peer(checker, 'X%d' % number)
                await extra.connect()
                await extra.close()
            refused = conformance.Peer(checker, 'X11')
            with self.assertRaises(conformance.CheckFailed) as caught:
                await refused.connect()
            self.assertIn('429', str(caught.exception))

        with tempfile.TemporaryDirectory() as folder:
            process, lines = self.start_mock(os.path.join(folder, 'state'), '--print-pairing', '--speed', '8',
                                             '--unlock-seconds', '1', '--limit-loopback', '--no-screen-recording')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK']))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_folders_connecting_and_opening_over_the_wire(self):
        async def scenario(link, tree):
            checker, peer = await self.paired(link)
            app = os.path.join(tree, 'Projects', 'app')
            try:
                welcome = peer.welcome
                for method in ('remote.folders', *wire.OPEN_ON_MAC):
                    self.assertIn(method, welcome['methods'])
                for method in wire.OPEN_ON_MAC:
                    self.assertIn(method, welcome['elevated'])
                state = (await peer.request('state'))['result']  # a read: no unlock needed
                plain_chat = next(c['id'] for c in state['chats'] if c['workspace'] is None)
                # locked: a listing of the Mac's folders needs the unlock
                self.assertEqual((await peer.act('remote.folders', {}))['code'], 'unlock_required')
                # a new folder: no proof, no connecting (and the same answer, locked or not)
                refused = await peer.act('set_workspace', {'id': plain_chat, 'path': app})
                self.assertEqual((refused['ok'], refused['code']), (False, 'proof_required'))
                # with the proof, which unlocks the phone as well
                done = await peer.exchange(peer.elevated_frame('set_workspace', {'id': plain_chat, 'path': app}))
                self.assertTrue(done['ok'], done)
                self.assertEqual(done['result']['workspace'], app)
                listing = await peer.act('remote.folders', {})
                self.assertTrue(listing['ok'], listing)
                self.assertEqual(set(listing['result']), {'home', 'path', 'parent', 'folders'})
                self.assertEqual([f['name'] for f in listing['result']['folders']], HOME_FOLDERS)  # not mock-state
                self.assertEqual(listing['result']['home'], tree)
                self.assertTrue((await peer.act('set_workspace', {'id': plain_chat, 'path': None}))['ok'])
                # new_chat in a new folder: the same rule, and the draft's first message then goes there
                refused = await peer.act('new_chat', {'workspace': app})
                self.assertEqual(refused['code'], 'proof_required')
                made = await peer.exchange(peer.elevated_frame('new_chat', {'workspace': app}))
                self.assertEqual(made['result']['workspace'], app)
                chat = made['result']['id']
                # the composer's Terminal command: a review card in that conversation, and Pebble's actions event
                refused = await peer.act('terminal_propose', {'id': chat, 'command': 'ls', 'network': False})
                self.assertEqual(refused['code'], 'proof_required')
                card = await peer.exchange(peer.elevated_frame('terminal_propose',
                                                               {'id': chat, 'command': 'ls', 'network': False}))
                self.assertEqual(card['result']['status'], 'awaiting_user_approval')
                seen = await peer.wait(lambda f: f.get('t') == 'evt' and f.get('event') == 'actions' and
                                       f['data']['chat_id'] == chat and
                                       any(a['status'] == 'pending' and a['kind'] == 'command'
                                           for a in f['data']['actions']), 5)
                self.assertIsNotNone(seen, 'no actions event carried the review card')
                # a source from the web, and an opening that the mock only pretends to do
                source = await peer.act('attach_url', {'id': chat, 'url': 'https://example.com/guide'})
                self.assertEqual((source['ok'], source['result']['characters']), (True, 2400))
                self.assertEqual((await peer.act('open_url', {'url': 'https://example.com/'}))['code'], 'proof_required')
                opened = await peer.exchange(peer.elevated_frame('open_url', {'url': 'https://example.com/'}))
                self.assertEqual(opened['result'], {'ok': True})
            finally:
                await peer.close()

        with tempfile.TemporaryDirectory() as folder:
            tree = make_tree(os.path.join(folder, 'home'))
            state = os.path.join(tree, 'mock-state')  # the mock's own folder is inside the tree it lists: never shown
            process, lines = self.start_mock(state, '--print-pairing', '--speed', '8', '--folders-root', tree)
            try:
                asyncio.run(scenario(lines['PAIRING_LINK'], tree))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_a_new_folder_over_the_wire(self):
        """Proposal v0.6 through the real mock process: a folder made with a proof is listed, and connects with the
        unlock alone; before the proof, nothing."""
        async def scenario(link, tree):
            checker, peer = await self.paired(link)
            projects = os.path.join(tree, 'Projects')
            made = os.path.join(projects, 'from the phone')
            try:
                self.assertIn('remote.folder_create', peer.welcome['methods'])
                self.assertIn('remote.folder_create', peer.welcome['elevated'])
                state = (await peer.request('state'))['result']
                plain_chat = next(c['id'] for c in state['chats'] if c['workspace'] is None)
                params = {'parent': projects, 'name': ' from the phone '}
                refused = await peer.act('remote.folder_create', params)  # no proof: proof_required, nothing made
                self.assertEqual((refused['ok'], refused['code']), (False, 'proof_required'))
                self.assertFalse(os.path.exists(made))
                answer = await peer.exchange(peer.elevated_frame('remote.folder_create', params))
                self.assertEqual(answer['result'], {'path': made, 'name': 'from the phone', 'is_project': False})
                self.assertEqual(os.listdir(made), [])
                listing = await peer.act('remote.folders', {'path': projects})
                self.assertIn(answer['result'], listing['result']['folders'])
                # one proof for "make it and connect it": the unlock is enough for the folder it just made
                other = await peer.act('set_workspace', {'id': plain_chat, 'path': os.path.join(projects, 'lib')})
                self.assertEqual(other['code'], 'proof_required')
                moved = await peer.act('set_workspace', {'id': plain_chat, 'path': made})
                self.assertTrue(moved['ok'], moved)
                self.assertEqual(moved['result']['workspace'], made)
                self.assertTrue((await peer.act('new_chat', {'workspace': made}))['ok'])
                again = await peer.exchange(peer.elevated_frame('remote.folder_create', params))
                self.assertEqual((again['ok'], again.get('code'), again['error']),
                                 (False, None, 'A folder with that name is already there.'))
                bad = await peer.exchange(peer.elevated_frame('remote.folder_create', {'parent': projects, 'name': '.x'}))
                self.assertEqual((bad['ok'], bad['code']), (False, 'bad_request'))
            finally:
                await peer.close()

        with tempfile.TemporaryDirectory() as folder:
            tree = make_tree(os.path.join(folder, 'home'))
            state = os.path.join(tree, 'mock-state')
            process, lines = self.start_mock(state, '--print-pairing', '--speed', '8', '--folders-root', tree)
            try:
                asyncio.run(scenario(lines['PAIRING_LINK'], tree))
            finally:
                self.stop_mock(process)

    async def begin_pairing(self, link, label='P', wait=30):
        """A software phone that has sent `pair` and is waiting for the Mac: (checker, its connection, the pair task)."""
        import conformance
        checker = conformance.Checker(link, timeout=10)
        checker.endpoint = checker.link['endpoints'][0]
        peer = await checker.peer(label)
        task = asyncio.create_task(peer.pair(checker.link['code'], checker.phone.device_key,
                                             checker.phone.approve_key, wait=wait))
        return checker, peer, task

    def stored_devices(self, state):
        path = os.path.join(state, 'devices.json')
        if not os.path.exists(path):
            return {}
        with open(path) as handle:
            return json.load(handle)['devices']

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_x1_the_mac_shows_the_code_the_formula_gives_after_about_1_5_seconds(self):
        async def scenario(link, process):
            checker, peer, task = await self.begin_pairing(link)
            started = time.monotonic()
            paired, welcome = await asyncio.wait_for(task, 20)
            took = time.monotonic() - started
            self.assertEqual((paired['t'], welcome['t']), ('paired', 'welcome'))
            self.assertGreaterEqual(took, 1.4)  # the default: about 1.5 s, so the phone can show its code
            self.assertLess(took, 4)
            transcript = wire.t_pair(checker.link['bid'], peer.nonce, checker.link['pin'], checker.link['code'],
                                     checker.phone.device_key.x963_b64u, checker.phone.approve_key.x963_b64u)
            self.assertEqual(process.stdout.readline().strip(), 'PAIRING_CODE=' + wire.sas_code(transcript))
            await peer.close()

        with tempfile.TemporaryDirectory() as folder:
            process, lines = self.start_mock(os.path.join(folder, 'state'), '--print-pairing',
                                             '--pair-confirm-delay', '1.5')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK'], process))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_x1_ask_mode_paired_never_comes_before_the_person_says_y(self):
        async def scenario(link, process, state):
            checker, peer, task = await self.begin_pairing(link)
            await asyncio.sleep(1.2)
            self.assertFalse(task.done())  # nothing but the challenge has come: no paired before the confirmation
            self.assertEqual([f['t'] for f in peer.frames], ['challenge'])
            self.assertEqual(self.stored_devices(state), {})  # and the phone is not stored yet
            # meanwhile the same code on another connection is refused: it is spent from the moment it verified
            other = await checker.peer('Q')
            refused, _ = await other.pair(checker.link['code'], wire.SigningKey(), wire.SigningKey())
            self.assertEqual((refused['t'], refused['code']), ('bye', 'bad_code'))
            self.assertFalse(task.done())
            process.stdin.write('y\n')
            process.stdin.flush()
            paired, welcome = await asyncio.wait_for(task, 10)
            self.assertEqual((paired['t'], welcome['t']), ('paired', 'welcome'))
            self.assertEqual(list(self.stored_devices(state)), [paired['device_id']])
            await peer.close()
            await other.close()

        with tempfile.TemporaryDirectory() as folder:
            state = os.path.join(folder, 'state')
            process, lines = self.start_mock(state, '--print-pairing', '--pair-confirm', 'ask')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK'], process, state))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_x1_ask_mode_n_is_bye_bad_code_and_the_code_is_spent(self):
        async def scenario(link, process, state):
            checker, peer, task = await self.begin_pairing(link)
            await asyncio.sleep(0.5)
            process.stdin.write('n\n')
            process.stdin.flush()
            paired, _ = await asyncio.wait_for(task, 10)
            self.assertEqual((paired['t'], paired['code']), ('bye', 'bad_code'))
            self.assertEqual(paired['error'], mock_bridge.PAIR_REFUSED)  # words for the person
            self.assertTrue(await peer.wait_closed(3))
            self.assertEqual(self.stored_devices(state), {})
            again = await checker.peer('Q')  # the code is spent: the same link cannot pair another phone either
            refused, _ = await again.pair(checker.link['code'], wire.SigningKey(), wire.SigningKey())
            self.assertEqual((refused['t'], refused['code']), ('bye', 'bad_code'))
            self.assertEqual(self.stored_devices(state), {})

        with tempfile.TemporaryDirectory() as folder:
            state = os.path.join(folder, 'state')
            process, lines = self.start_mock(state, '--print-pairing', '--pair-confirm', 'ask')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK'], process, state))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_x1_no_answer_within_the_timeout_is_bye_bad_code(self):
        """The two-minute rule, as --pair-confirm-timeout lets a test see it: nobody answers `ask`."""
        async def scenario(link, state):
            checker, peer, task = await self.begin_pairing(link)
            started = time.monotonic()
            paired, _ = await asyncio.wait_for(task, 20)
            took = time.monotonic() - started
            self.assertEqual((paired['t'], paired['code']), ('bye', 'bad_code'))
            self.assertEqual(paired['error'], mock_bridge.PAIR_REFUSED)
            self.assertGreaterEqual(took, 0.9)
            self.assertLess(took, 5)
            self.assertEqual(self.stored_devices(state), {})
            again = await checker.peer('Q')
            refused, _ = await again.pair(checker.link['code'], wire.SigningKey(), wire.SigningKey())
            self.assertEqual((refused['t'], refused['code']), ('bye', 'bad_code'))  # spent

        with tempfile.TemporaryDirectory() as folder:
            state = os.path.join(folder, 'state')
            process, lines = self.start_mock(state, '--print-pairing', '--pair-confirm', 'ask',
                                             '--pair-confirm-timeout', '1')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK'], state))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_x1_a_phone_that_leaves_before_the_person_answers_is_not_stored_and_the_code_is_spent(self):
        async def scenario(link, process, state):
            checker, peer, task = await self.begin_pairing(link)
            await asyncio.sleep(0.5)
            await peer.close()
            await asyncio.wait_for(task, 5)
            process.stdin.write('y\n')  # the person answers too late: nobody is there to pair
            process.stdin.flush()
            await asyncio.sleep(0.4)
            self.assertEqual(self.stored_devices(state), {})
            again = await checker.peer('Q')
            refused, _ = await again.pair(checker.link['code'], wire.SigningKey(), wire.SigningKey())
            self.assertEqual((refused['t'], refused['code']), ('bye', 'bad_code'))

        with tempfile.TemporaryDirectory() as folder:
            state = os.path.join(folder, 'state')
            process, lines = self.start_mock(state, '--print-pairing', '--pair-confirm', 'ask')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK'], process, state))
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_x1_conformance_checks_a_refusal_and_says_why_a_normal_run_fails_on_it(self):
        import conformance
        with tempfile.TemporaryDirectory() as folder:
            process, lines = self.start_mock(os.path.join(folder, 'state'), '--print-pairing',
                                             '--pair-confirm', 'refuse')
            try:
                done, results = self.run_conformance(lines['PAIRING_LINK'], folder, '--expect-pair-refused',
                                                     '--pair-wait', '20')
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assertEqual([(r['name'], r['ok']) for r in results],
                                 [('transport: TLS 1.3, the pinned key, the subprotocol', True),
                                  (conformance.Checker.X1_REFUSED, True), (conformance.Checker.X1_SPENT, True)])
                self.assertIn('pairing code', done.stdout)  # the code the Mac must show is printed for the person
                process.send_signal(signal.SIGUSR1)  # a fresh link for a normal run, which never gets paired
                fresh = None
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline and fresh is None:
                    line = process.stdout.readline().strip()
                    if line.startswith('PAIRING_LINK='):
                        fresh = line.partition('=')[2]
                self.assertIsNotNone(fresh)
                done, results = self.run_conformance(fresh, folder, '--pair-wait', '20')
                self.assertEqual(done.returncode, 1)
                pairing = next(r for r in results if r['name'].startswith('pairing works'))
                self.assertFalse(pairing['ok'])
                self.assertIn('not confirmed on the Mac', pairing['detail'])
            finally:
                self.stop_mock(process)

    @unittest.skipUnless(OPENSSL, 'openssl is not installed')
    def test_s05_the_unlock_ends_with_remote_lock_and_with_the_devices_last_connection(self):
        async def scenario(link):
            checker, peer = await self.paired(link)

            async def unlock(connection):
                done = await connection.exchange(connection.elevated_frame('remote.unlock', {}))
                self.assertTrue(done['ok'], done)

            try:
                self.assertIn('remote.lock', peer.welcome['methods'])
                self.assertNotIn('remote.lock', peer.welcome['elevated'])
                self.assertEqual((await peer.act('new_chat', {}))['code'], 'unlock_required')
                await unlock(peer)
                self.assertTrue((await peer.act('new_chat', {}))['ok'])
                # remote.lock: a read ({} to {}, no idem) that ends the unlock at once
                locked = await peer.request('remote.lock', {})
                self.assertEqual((locked['ok'], locked['result']), (True, {}))
                self.assertEqual((await peer.act('new_chat', {}))['code'], 'unlock_required')
                self.assertTrue((await peer.request('state'))['ok'])  # a read still works
                await unlock(peer)
                # a newer connection of the device replaces this one: the device is still connected, still unlocked
                second = await checker.peer('P2')
                self.assertEqual((await second.hello())['t'], 'welcome')
                self.assertTrue((await second.act('new_chat', {}))['ok'])
                await peer.close()  # the replaced one closing is not the last connection
                await asyncio.sleep(0.3)
                self.assertTrue((await second.act('new_chat', {}))['ok'])
                # the last connection closing ends the unlock
                await second.close()
                await asyncio.sleep(0.4)
                third = await checker.peer('P3')
                self.assertEqual((await third.hello())['t'], 'welcome')
                self.assertEqual((await third.act('new_chat', {}))['code'], 'unlock_required')
                self.assertEqual((await third.request('remote.lock', {}))['result'], {})  # locked already: still {}
                await third.close()
            finally:
                await peer.close()

        with tempfile.TemporaryDirectory() as folder:
            process, lines = self.start_mock(os.path.join(folder, 'state'), '--print-pairing', '--speed', '8')
            try:
                asyncio.run(scenario(lines['PAIRING_LINK']))
            finally:
                self.stop_mock(process)

    def test_the_mock_refuses_a_folders_root_that_is_not_a_folder(self):
        with tempfile.TemporaryDirectory() as folder:
            done = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'mock_bridge.py'), '--host', '127.0.0.1',
                                   '--port', '0', '--state-dir', os.path.join(folder, 'state'), '--quiet',
                                   '--folders-root', os.path.join(folder, 'nope')],
                                  capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
        self.assertNotEqual(done.returncode, 0)
        self.assertIn('--folders-root', done.stderr)


@unittest.skipUnless(OPENSSL, 'openssl is not installed')
class InProcessConformance(unittest.IsolatedAsyncioTestCase):
    """The mock on 127.0.0.1 in this event loop, and a conformance checker for it: for tests that change the bridge (a
    fault, a pairing mode) and run rows of the checker against it."""

    async def asyncSetUp(self):
        import conformance
        self.conformance = conformance
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.tree = make_tree(os.path.join(self.folder.name, 'home'))
        self.codes = []  # the six-digit codes the bridge asked the person to confirm (X-1)

    async def serve(self, **options):
        """The bridge, listening, and a checker that has its pairing link (nothing paired yet)."""
        state = os.path.join(self.tree, 'mock-state')
        identity = mock_bridge.Identity(state, OPENSSL)
        registry = mock_bridge.Registry(os.path.join(state, 'devices.json'))
        options.setdefault('pair_confirm_delay', 0.05)
        self.bridge = mock_bridge.Bridge(identity, registry, name='Test Mac', speed=8, state_dir=state,
                                         folders_root=self.tree, **options)
        self.bridge.on_pairing_code = self.codes.append
        self.server = await asyncio.start_server(self.bridge.handle, '127.0.0.1', 0, ssl=identity.tls_context(),
                                                 ssl_handshake_timeout=10, limit=1 << 16)
        self.addAsyncCleanup(self.stop)
        self.bridge.endpoints = [wire.format_endpoint('127.0.0.1', self.server.sockets[0].getsockname()[1])]
        self.checker = self.conformance.Checker(self.bridge.open_pairing(), timeout=10)
        self.checker.endpoint = self.checker.link['endpoints'][0]
        self.checker.pacer = self.conformance.Pacer(10 ** 6, 10 ** 6)  # not testing the rate
        self.peer = None

    async def start(self, **options):
        """serve(), then pair through the checker's own pairing row, then the welcome, the reads and the unlock: the
        checker is holding a conversation, and `self.peer` is its connection."""
        await self.serve(**options)
        with contextlib.redirect_stdout(io.StringIO()):
            await self.checker.c_pair()
            self.peer = self.checker.main_peer
            self.bridge.buckets[self.checker.phone.device_id] = mock_bridge.TokenBucket(10 ** 6, 10 ** 6)
            await self.checker.c_welcome(self.peer)
            await self.checker.c_reads(self.peer)
            await self.checker.c_unlock(self.peer)

    async def stop(self):
        for task in list(self.bridge.sim.tasks.values()):
            task.cancel()
        for peer in self.checker.peers:
            await peer.close()
        for conn in list(self.bridge.conns):
            conn.close()
        self.server.close()
        with contextlib.suppress(asyncio.TimeoutError, TimeoutError):
            await asyncio.wait_for(self.server.wait_closed(), 5)

    async def rows(self):
        """Run the v0.5 rows after the unlock; {row name: its result}."""
        before = len(self.checker.results)
        with contextlib.redirect_stdout(io.StringIO()):
            await self.checker.run_v05(self.peer)
        return {r['name']: r for r in self.checker.results[before:]}

    async def row(self, name, function, *args):
        """One row, as the checker runs it; its result."""
        with contextlib.redirect_stdout(io.StringIO()):
            await self.checker.check(name, function, *args)
        return self.checker.results[-1]

    def only_failing(self, rows, *names):
        self.assertEqual(sorted(name for name, r in rows.items() if r['ok'] is not True), sorted(names),
                         {name: r['detail'] for name, r in rows.items() if r['ok'] is not True})


class ConformanceV05Tests(InProcessConformance):
    """The v0.5 rows of the conformance checker, run against the mock in this process: they pass a bridge that follows
    the proposal, and each one fails a bridge that breaks the rule it checks (and only that one)."""

    async def test_a_bridge_that_follows_the_proposal_passes_every_row(self):
        await self.start()
        self.assertTrue(self.checker.v05)
        rows = await self.rows()
        self.assertEqual(list(rows), self.conformance.Checker.V05_ROWS)
        self.only_failing(rows)
        self.assertEqual([r['ok'] for r in rows.values()], [True] * len(rows))  # not one skipped
        # what the rows did: the checker's own conversation is back with the Companion, and no link is left behind
        self.assertIsNone(self.bridge.sim.chats[self.checker.chat_id]['workspace'])
        self.assertEqual(sorted(name for name in os.listdir(self.tree) if name.startswith('pebble-remote-')), [])
        self.assertEqual(self.checker.folder_home, self.tree)
        # the folder it goes into is the first that macOS does not ask the person about before it is read
        self.assertEqual(self.checker.folder_child['name'], 'Archive')

    async def test_the_checker_can_leave_a_conversation_alone_with_no_connect(self):
        await self.start()
        self.checker.connect = False
        rows = await self.rows()
        self.only_failing(rows)
        self.assertIn('not tried (--no-connect)', rows[self.conformance.Checker.V05_WORKSPACE]['detail'])

    async def test_hidden_and_protected_folders_in_the_listing_fail_the_checker(self):
        await self.start()
        checker = self.conformance.Checker
        with mock.patch.object(self.bridge.folders, 'left_out', lambda path, name, info=None: None):
            rows = await self.rows()
        self.assertFalse(rows[checker.V05_LISTING]['ok'])
        self.assertIn('hidden folder is listed', rows[checker.V05_LISTING]['detail'])
        self.only_failing(rows, *checker.V05_ROWS[:6])  # the rows that need the listing do not run

    async def test_a_bridge_that_lets_a_path_outside_home_or_a_hidden_one_through_fails(self):
        await self.start()
        checker = self.conformance.Checker
        folders = self.bridge.folders

        def lax(path):  # no rule at all: whatever the path is, it is listed
            folders.bases = wire.protected_bases(folders.home, folders.extra)
            return folders.home if path is None else os.path.realpath(path)

        with mock.patch.object(folders, 'locate', lax):
            rows = await self.rows()
        self.only_failing(rows, checker.V05_OUTSIDE, checker.V05_PRIVATE, checker.V05_LINKS, checker.V05_WORKSPACE)
        self.assertIn('expected not_allowed', rows[checker.V05_OUTSIDE]['detail'])
        self.assertIn('was connected', rows[checker.V05_WORKSPACE]['detail'])  # and a proof did not make /usr a project
        self.assertIsNone(self.bridge.sim.chats[self.checker.chat_id]['workspace'])  # the checker put it back

    async def test_a_bridge_that_follows_links_fails_only_the_link_row(self):
        """claude-w's 10:53 addition: a path that is itself a link gets not_allowed, even when the link points at a
        folder inside home. A bridge that resolves a link first and then applies every other rule to where it leads
        passes everything else and fails this row."""
        await self.start()
        checker = self.conformance.Checker
        folders = self.bridge.folders
        locate = folders.locate

        def follows(path):
            return locate(os.path.realpath(path) if isinstance(path, str) and path.startswith('/') else path)

        with mock.patch.object(folders, 'locate', follows):
            rows = await self.rows()
        self.only_failing(rows, checker.V05_LINKS)
        self.assertIn('a link to a folder inside home', rows[checker.V05_LINKS]['detail'])
        self.assertEqual(sorted(name for name in os.listdir(self.tree) if name.startswith('pebble-remote-')), [])
        self.assertIsNone(self.bridge.sim.chats[self.checker.chat_id]['workspace'])

    async def test_the_link_row_is_skipped_where_the_checker_cannot_make_a_link(self):
        await self.start()
        checker = self.conformance.Checker
        self.checker.link_probe = False
        rows = await self.rows()
        self.assertEqual({name for name, r in rows.items() if r['ok'] is not True}, {checker.V05_LINKS})  # skipped
        self.assertIsNone(rows[checker.V05_LINKS]['ok'])
        self.assertIn('--no-link-probe', rows[checker.V05_LINKS]['detail'])
        self.checker.link_probe = True
        real_endpoint = self.checker.endpoint
        self.checker.endpoint = ('192.168.9.9', real_endpoint[1])  # not this Mac: the checker cannot make a link there
        try:
            rows = await self.rows()
        finally:
            self.checker.endpoint = real_endpoint
        self.assertIsNone(rows[checker.V05_LINKS]['ok'])
        self.assertIn('only on the Mac the bridge runs on', rows[checker.V05_LINKS]['detail'])
        # and it does not write in a folder that is not the user's own or a temporary one
        self.bridge.folders.home = '/usr'
        rows = await self.rows()
        self.assertIsNone(rows[checker.V05_LINKS]['ok'])

    async def test_a_bridge_that_connects_a_new_folder_without_a_proof_fails_only_that_row(self):
        await self.start()
        checker = self.conformance.Checker
        original = self.bridge.needs_proof
        with mock.patch.object(self.bridge, 'needs_proof',
                               lambda method, params: False if method == 'set_workspace' else original(method, params)):
            rows = await self.rows()
        self.only_failing(rows, checker.V05_WORKSPACE)
        self.assertIn('with no proof', rows[checker.V05_WORKSPACE]['detail'])
        self.assertIsNone(self.bridge.sim.chats[self.checker.chat_id]['workspace'])  # put back

    async def test_a_bridge_that_forwards_new_chat_as_it_is_fails_only_the_new_chat_row(self):
        """The reading of claude-w's 10:53 answer ("forwarded as is"): any phone with the unlock could connect any folder
        of home through new_chat, with no Face ID. Its own row says so, and the set_workspace row still passes."""
        await self.start()
        checker = self.conformance.Checker
        original = self.bridge.needs_proof
        with mock.patch.object(self.bridge, 'needs_proof',
                               lambda method, params: False if method == 'new_chat' else original(method, params)):
            rows = await self.rows()
        self.only_failing(rows, checker.V05_NEW_CHAT)
        self.assertIn('way around set_workspace', rows[checker.V05_NEW_CHAT]['detail'])

    async def test_an_opening_method_that_needs_no_proof_fails_its_row(self):
        await self.start()
        checker = self.conformance.Checker
        with mock.patch.object(mock_bridge, 'ELEVATED_ALWAYS', mock_bridge.ELEVATED_ALWAYS - {'open_url'}):
            rows = await self.rows()
        self.only_failing(rows, checker.V05_OPEN)
        self.assertIn('open_url', rows[checker.V05_OPEN]['detail'])

    async def test_a_listing_of_the_wrong_shape_fails_the_first_row(self):
        await self.start()
        checker = self.conformance.Checker
        folders = self.bridge.folders
        original = folders.listing
        many = [{'name': 'f%03d' % n, 'path': os.path.join(self.tree, 'f%03d' % n), 'is_project': False}
                for n in range(501)]
        faults = {
            'parent must be null': lambda path=None: {**original(path), 'parent': ''},
            'not sorted': lambda path=None: {**original(path), 'folders': original(path)['folders'][::-1]},
            'at most 500': lambda path=None: {**original(path), 'folders': many},
            'is_project is not true or false': lambda path=None: {
                **original(path), 'folders': [{**row, 'is_project': 1} for row in original(path)['folders']]},
            'path is not an absolute folder path': lambda path=None: {**original(path), 'path': 'home'},
            'the answer has no "home"': lambda path=None: {k: v for k, v in original(path).items() if k != 'home'},
        }
        for words, fault in faults.items():
            with self.subTest(words), mock.patch.object(folders, 'listing', fault):
                rows = await self.rows()
                self.assertFalse(rows[checker.V05_LISTING]['ok'])
                self.assertIn(words, rows[checker.V05_LISTING]['detail'])

    async def test_remote_folders_without_the_unlock_fails_its_row(self):
        await self.start()
        with mock.patch.object(self.bridge, 'is_unlocked', lambda device: True):  # a bridge that never asks
            self.bridge.unlocked.clear()
            result = await self.row(self.conformance.Checker.V05_LOCKED, self.checker.c_folders_locked, self.peer)
        self.assertFalse(result['ok'])
        self.assertIn('expected unlock_required', result['detail'])

    async def test_a_bridge_without_remote_folders_is_judged_by_v03_alone(self):
        legacy = [m for m in mock_bridge.METHODS if m not in ('remote.folders', 'remote.folder_create') and
                  m not in wire.OPEN_ON_MAC]  # a v0.3 bridge: v0.6 builds on v0.5's folders
        elevated = [e for e in mock_bridge.ELEVATED if e in legacy or e.startswith('setting:')]
        with mock.patch.object(mock_bridge, 'METHODS', legacy), mock.patch.object(mock_bridge, 'METHOD_SET',
                                                                                    set(legacy)), \
                mock.patch.object(mock_bridge, 'ELEVATED', elevated):
            await self.start()
            self.assertFalse(self.checker.v05)
            result = await self.row('not allowed', self.checker.c_not_allowed, self.peer)
            self.assertTrue(result['ok'])
            self.assertIn('the Mac screen', result['detail'])  # v0.3's 16: open_url is refused again
            rows = await self.rows()
        self.assertEqual(len(rows), 1)
        (row,) = rows.values()
        self.assertIsNone(row['ok'])  # a skipped row, not a failure
        self.assertIn('v0.3 only', row['detail'])

    async def test_opening_methods_without_remote_folders_fail_the_welcome_row(self):
        without_folders = [m for m in mock_bridge.METHODS if m not in ('remote.folders', 'remote.folder_create')]
        with mock.patch.object(mock_bridge, 'METHODS', without_folders):
            with self.assertRaises(self.conformance.CheckFailed) as caught:
                await self.start()  # its welcome row is the first thing the checker runs after pairing
        self.assertFalse(self.checker.v05)
        self.assertIn('open_url', str(caught.exception))


class ConformanceV06Tests(InProcessConformance):
    """The v0.6 rows of the conformance checker, run against the mock in this process: they pass a bridge that follows the
    proposal, and each one fails a bridge that breaks the rule it checks (and only that one). Every row makes its folders in
    the test tree and takes them away again."""

    async def rows06(self):
        """The v0.5 rows first (they find the home folder and a folder to go into), then the v0.6 ones: {name: result}."""
        await self.rows()
        before = len(self.checker.results)
        with contextlib.redirect_stdout(io.StringIO()):
            await self.checker.run_v06(self.peer)
        return {r['name']: r for r in self.checker.results[before:]}

    def tidy(self):
        """Nothing the checker made is left in the tree, or in the folder above it."""
        self.assertEqual(sorted(name for name in os.listdir(self.tree) if name.startswith('pebble-remote-')), [])
        self.assertEqual(os.listdir(self.folder.name), ['home'])
        self.assertIsNone(self.bridge.sim.chats[self.checker.chat_id]['workspace'])  # its conversation is in the Companion

    async def test_a_bridge_that_follows_the_proposal_passes_every_row(self):
        await self.start()
        self.assertTrue(self.checker.v05 and self.checker.v06)
        rows = await self.rows06()
        self.assertEqual(list(rows), self.conformance.Checker.V06_ROWS)
        self.only_failing(rows)
        self.assertEqual([r['ok'] for r in rows.values()], [True] * 3)  # not one skipped
        self.tidy()
        device = self.checker.phone.device_id  # one folder for each row, all made by the checker's own device
        self.assertEqual((list(self.bridge.made), len(self.bridge.made[device])), ([device], 3))

    async def test_the_rows_are_skipped_where_the_checker_may_not_or_cannot_write(self):
        await self.start()
        checker = self.conformance.Checker
        self.checker.create_probe = False
        rows = await self.rows06()
        self.assertEqual([r['ok'] for r in rows.values()], [None] * 3)
        self.assertIn('--no-create-probe', rows[checker.V06_CREATE]['detail'])
        self.checker.create_probe = True
        self.checker.connect = False  # --no-connect leaves the conversation alone: only the connecting row is skipped
        rows = await self.rows06()
        self.assertEqual({name: r['ok'] for name, r in rows.items()},
                         {checker.V06_CREATE: True, checker.V06_REFUSALS: True, checker.V06_CONNECT: None})
        self.assertIn('--no-connect', rows[checker.V06_CONNECT]['detail'])
        self.checker.connect = True
        real_endpoint = self.checker.endpoint
        self.checker.endpoint = ('192.168.9.9', real_endpoint[1])  # not this Mac: a folder cannot be taken away there
        try:
            rows = await self.rows06()
        finally:
            self.checker.endpoint = real_endpoint
        self.assertEqual([r['ok'] for r in rows.values()], [None] * 3)
        self.assertIn('only on the Mac the bridge runs on', rows[checker.V06_CREATE]['detail'])
        self.bridge.folders.home = '/usr'  # and never in a folder that is not the user's own or a temporary one
        rows = await self.rows06()
        self.assertEqual([r['ok'] for r in rows.values()], [None] * 3)
        self.bridge.folders.home = self.tree
        self.tidy()

    async def test_the_link_cases_are_left_out_with_no_link_probe(self):
        await self.start()
        self.checker.link_probe = False
        rows = await self.rows06()
        self.assertIn('links not tried (--no-link-probe)', rows[self.conformance.Checker.V06_REFUSALS]['detail'])
        self.assertTrue(rows[self.conformance.Checker.V06_REFUSALS]['ok'])

    async def test_a_bridge_that_makes_a_folder_without_a_proof_fails_only_the_create_row(self):
        await self.start()
        checker = self.conformance.Checker
        with mock.patch.object(mock_bridge, 'ELEVATED_ALWAYS', mock_bridge.ELEVATED_ALWAYS - {'remote.folder_create'}):
            rows = await self.rows06()
        self.only_failing(rows, checker.V06_CREATE)
        self.assertIn('expected proof_required', rows[checker.V06_CREATE]['detail'])
        self.tidy()  # the folder it made without a proof was taken away again

    async def test_a_bridge_that_does_not_keep_to_the_name_rules_fails_only_the_refusals_row(self):
        await self.start()
        checker = self.conformance.Checker
        with mock.patch.object(wire, 'folder_name_problem', lambda name: None):
            rows = await self.rows06()
        self.only_failing(rows, checker.V06_REFUSALS)
        self.assertIn('a leading dot', rows[checker.V06_REFUSALS]['detail'])
        self.tidy()  # a hidden folder, a name with a colon and the like were made, found and removed

    async def test_a_bridge_that_makes_a_folder_outside_home_fails_only_the_refusals_row(self):
        await self.start()
        checker = self.conformance.Checker
        folders = self.bridge.folders

        def lax(path):  # no rule at all: whatever the parent is, it is used
            folders.bases = wire.protected_bases(folders.home, folders.extra)
            return folders.home if path is None else os.path.realpath(path)

        with mock.patch.object(folders, 'locate', lax):
            rows = await self.rows06()
        self.only_failing(rows, checker.V06_REFUSALS)
        self.assertIn('expected not_allowed', rows[checker.V06_REFUSALS]['detail'])
        self.assertIn('a folder was made for the folder above home', rows[checker.V06_REFUSALS]['detail'])
        self.tidy()  # in the folder above home too

    async def test_a_bridge_that_gives_a_name_already_there_a_code_fails_only_the_refusals_row(self):
        await self.start()
        checker = self.conformance.Checker
        create = self.bridge.folders.create

        def coded(parent, name):
            try:
                return create(parent, name)
            except mock_bridge.FolderRefused as exc:
                if exc.words == mock_bridge.FOLDER_WORDS['exists']:
                    raise mock_bridge.FolderRefused(exc.words, 'bad_request') from None
                raise

        with mock.patch.object(self.bridge.folders, 'create', coded):
            rows = await self.rows06()
        self.only_failing(rows, checker.V06_REFUSALS)
        self.assertIn('expected words with no code', rows[checker.V06_REFUSALS]['detail'])
        self.tidy()

    async def test_a_bridge_that_answers_another_shape_fails_only_the_create_row(self):
        await self.start()
        checker = self.conformance.Checker
        create = self.bridge.folders.create
        for words, fault in (('is not {path, name, is_project}', lambda made: {**made, 'created': True}),
                             ('is not the new folder as remote.folders gives an entry',
                              lambda made: {**made, 'is_project': 'no'}),
                             ('is not the new folder as remote.folders gives an entry',
                              lambda made: {**made, 'name': made['name'].upper()})):
            with self.subTest(words), mock.patch.object(self.bridge.folders, 'create',
                                                        lambda parent, name: fault(create(parent, name))):
                rows = await self.rows06()
                self.only_failing(rows, checker.V06_CREATE)
                self.assertIn(words, rows[checker.V06_CREATE]['detail'])
        self.tidy()

    async def test_a_bridge_that_does_not_remember_what_a_device_made_fails_only_the_connect_row(self):
        await self.start()
        checker = self.conformance.Checker
        with mock.patch.object(self.bridge, 'remember_made', lambda device, path: None):
            rows = await self.rows06()
        self.only_failing(rows, checker.V06_CONNECT)
        self.assertIn('counts as known for ten minutes', rows[checker.V06_CONNECT]['detail'])
        self.tidy()

    async def test_a_bridge_that_remembers_more_than_the_folder_made_fails_only_the_connect_row(self):
        """After a device made one folder, every folder is connected with the unlock alone: only the one that was made may be."""
        await self.start()
        checker = self.conformance.Checker
        wide = lambda device, method, params: method in ('set_workspace', 'new_chat') and bool(self.bridge.made.get(device))
        with mock.patch.object(self.bridge, 'made_here', wide):
            rows = await self.rows06()
        self.only_failing(rows, checker.V06_CONNECT)
        self.assertIn('only the folder this device made may be known', rows[checker.V06_CONNECT]['detail'])
        self.tidy()

    async def test_a_bridge_without_remote_folder_create_is_judged_by_v05_alone(self):
        legacy = [m for m in mock_bridge.METHODS if m != 'remote.folder_create']
        elevated = [e for e in mock_bridge.ELEVATED if e != 'remote.folder_create']
        with mock.patch.object(mock_bridge, 'METHODS', legacy), mock.patch.object(mock_bridge, 'METHOD_SET',
                                                                                    set(legacy)), \
                mock.patch.object(mock_bridge, 'ELEVATED', elevated):
            await self.start()
            self.assertTrue(self.checker.v05)
            self.assertFalse(self.checker.v06)
            rows = await self.rows06()
        (row,) = rows.values()
        self.assertIsNone(row['ok'])  # a skipped row, not a failure
        self.assertIn('v0.5 only', row['detail'])
        self.assertEqual(self.checker.v06_rows(), [])

    async def test_remote_folder_create_without_remote_folders_fails_the_welcome_row(self):
        without = [m for m in mock_bridge.METHODS if m != 'remote.folders' and m not in wire.OPEN_ON_MAC]
        with mock.patch.object(mock_bridge, 'METHODS', without), mock.patch.object(mock_bridge, 'METHOD_SET',
                                                                                     set(without)):
            with self.assertRaises(self.conformance.CheckFailed) as caught:
                await self.start()
        self.assertTrue(self.checker.v06 and not self.checker.v05)
        self.assertIn('remote.folder_create is offered without remote.folders', str(caught.exception))

    async def test_an_offered_method_that_is_not_listed_as_elevated_fails_the_welcome_row(self):
        elevated = [e for e in mock_bridge.ELEVATED if e != 'remote.folder_create']
        with mock.patch.object(mock_bridge, 'ELEVATED', elevated):
            with self.assertRaises(self.conformance.CheckFailed) as caught:
                await self.start()
        self.assertIn('remote.folder_create', str(caught.exception))


class ConformanceX1AndS05Tests(InProcessConformance):
    """X-1 (the person confirms each pairing on the Mac) and S-05 (remote.lock, and an unlock that ends with the
    device's last connection): the rows pass a bridge that follows them, and fail one that does not."""

    # -- X-1 -----------------------------------------------------------------------------------------------------------

    async def test_the_x1_rows_pass_a_bridge_that_waits_for_the_person(self):
        checker = self.conformance.Checker
        await self.start(pair_confirm_delay=1.2)
        formula = await self.row(checker.X1_FORMULA, self.checker.c_sas_formula)
        confirmed = await self.row(checker.X1_CONFIRMED, self.checker.c_pair_confirmed)
        self.assertEqual((formula['ok'], confirmed['ok']), (True, True), (formula['detail'], confirmed['detail']))
        self.assertGreaterEqual(self.checker.pair_seconds, 1.2)
        # the bridge asked the person to confirm exactly the code the checker computed and showed for the same T_pair
        self.assertEqual(self.codes, [self.checker.pair_sas])
        self.assertRegex(self.checker.pair_sas, r'^\d{6}$')

    async def test_a_bridge_that_confirms_by_itself_at_once_fails_the_timing_row(self):
        checker = self.conformance.Checker
        await self.start(pair_confirm_delay=0)
        formula = await self.row(checker.X1_FORMULA, self.checker.c_sas_formula)
        confirmed = await self.row(checker.X1_CONFIRMED, self.checker.c_pair_confirmed)
        self.assertTrue(formula['ok'])
        self.assertFalse(confirmed['ok'])
        self.assertIn('until the person confirms', confirmed['detail'])

    async def test_a_cancelled_pairing_passes_the_refusal_rows(self):
        checker = self.conformance.Checker
        await self.serve(pair_confirm='refuse')
        self.checker.expect_pair_refused = True
        with contextlib.redirect_stdout(io.StringIO()):
            await self.checker._run_refused()
        by_name = {r['name']: r for r in self.checker.results}
        self.assertEqual([(r['name'], r['ok']) for r in self.checker.results],
                         [('transport: TLS 1.3, the pinned key, the subprotocol', True), (checker.X1_REFUSED, True),
                          (checker.X1_SPENT, True)], {n: r['detail'] for n, r in by_name.items()})
        self.assertIn('bye bad_code', by_name[checker.X1_REFUSED]['detail'])
        self.assertEqual(self.bridge.registry.devices, {})  # nothing was stored

    async def test_the_normal_run_says_why_a_cancelled_pairing_fails(self):
        await self.serve(pair_confirm='refuse')
        with self.assertRaises(self.conformance.CheckFailed) as caught, contextlib.redirect_stdout(io.StringIO()):
            await self.checker.c_pair()
        self.assertIn('not confirmed on the Mac', str(caught.exception))

    async def test_no_answer_for_the_timeout_is_a_refusal_too(self):
        """The two-minute rule, with a shortened timeout: the person never answers (the bridge would wait 5 s to
        confirm, and gives up after 0.4 s)."""
        checker = self.conformance.Checker
        await self.serve(pair_confirm='auto', pair_confirm_delay=5, pair_confirm_timeout=0.4)
        with contextlib.redirect_stdout(io.StringIO()):
            await self.checker._run_refused()
        self.assertEqual([r['ok'] for r in self.checker.results], [True, True, True],
                         [r['detail'] for r in self.checker.results])
        self.assertLess(float(re.search(r'after ([0-9.]+) s', self.checker.results[1]['detail']).group(1)), 3)

    async def test_a_bridge_that_pairs_instead_fails_the_refusal_rows(self):
        checker = self.conformance.Checker
        await self.serve(pair_confirm='auto')  # it confirms by itself, so --expect-pair-refused finds a pairing
        with contextlib.redirect_stdout(io.StringIO()):
            await self.checker._run_refused()
        by_name = {r['name']: r for r in self.checker.results}
        self.assertFalse(by_name[checker.X1_REFUSED]['ok'])
        self.assertIn('expected bye bad_code', by_name[checker.X1_REFUSED]['detail'])
        self.assertFalse(by_name[checker.X1_SPENT]['ok'])  # not run

    # -- S-05 ----------------------------------------------------------------------------------------------------------

    async def test_the_s05_rows_pass_a_bridge_that_follows_them(self):
        checker = self.conformance.Checker
        await self.start()
        lock = await self.row(checker.S05_LOCK, self.checker.c_lock, self.peer)
        self.assertTrue(lock['ok'], lock['detail'])
        self.assertTrue(self.bridge.is_unlocked(self.checker.phone.device_id))  # unlocked again with a proof
        last = await self.row(checker.S05_LAST, self.checker.c_last_connection)
        self.assertTrue(last['ok'], last['detail'])

    async def test_a_lock_that_does_not_lock_fails_its_row(self):
        checker = self.conformance.Checker
        await self.start()
        original = self.bridge.remote
        lazy = lambda conn, method, params: ({'ok': True, 'result': {}}, None) if method == 'remote.lock' \
            else original(conn, method, params)  # answers {} but leaves the unlock
        with mock.patch.object(self.bridge, 'remote', lazy):
            lock = await self.row(checker.S05_LOCK, self.checker.c_lock, self.peer)
        self.assertFalse(lock['ok'])
        self.assertIn('expected unlock_required', lock['detail'])
        self.assertTrue(self.bridge.is_unlocked(self.checker.phone.device_id))

    async def test_a_bridge_without_remote_lock_fails_its_row(self):
        checker = self.conformance.Checker
        with mock.patch.object(mock_bridge, 'METHODS', [m for m in mock_bridge.METHODS if m != 'remote.lock']):
            await self.start()
            lock = await self.row(checker.S05_LOCK, self.checker.c_lock, self.peer)
        self.assertFalse(lock['ok'])
        self.assertIn('lacks remote.lock', lock['detail'])

    async def test_an_unlock_that_outlives_the_last_connection_fails_its_row(self):
        checker = self.conformance.Checker

        class Sticky(dict):  # a bridge whose unlock never ends when a connection closes
            def pop(self, key, default=None):
                return default

        await self.start()
        self.bridge.unlocked = Sticky(self.bridge.unlocked)
        last = await self.row(checker.S05_LAST, self.checker.c_last_connection)
        self.assertFalse(last['ok'])
        self.assertIn("outlived the device's last connection", last['detail'])


if __name__ == '__main__':
    unittest.main()
