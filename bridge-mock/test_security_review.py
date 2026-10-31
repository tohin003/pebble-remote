"""Tests for the security review of 2026-10-30 (docs/reviews/security-2026-10-30.md): the mock bridge's fixes (M-1,
M-2) and the conformance rows the review added (K-1 to K-4, which test_mock.py's end-to-end run executes against the
mock).

    python3 -I -B -m unittest discover -s bridge-mock -p 'test_*.py'   (from the repository root)
"""

import asyncio
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import remote_wire as wire  # noqa: E402
import mock_bridge  # noqa: E402
import conformance  # noqa: E402

mock_bridge.QUIET = True


class StubIdentity:
    bid, pin = 'b-test', 'pin-test'


class MockSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.folder = tempfile.TemporaryDirectory()
        registry = mock_bridge.Registry(os.path.join(self.folder.name, 'devices.json'))
        self.bridge = mock_bridge.Bridge(StubIdentity(), registry, name='Test Mac', speed=50)

    async def asyncTearDown(self):
        for task in list(self.bridge.sim.tasks.values()):
            task.cancel()
        self.folder.cleanup()

    def sent(self, conn):
        return [json.loads(text) for text in conn.queue]

    # M-1 -------------------------------------------------------------------------------------------------------------

    def test_deep_json_is_unreadable_not_a_recursion_error(self):
        with self.assertRaises(ValueError):
            mock_bridge.loads('[' * 300000 + ']' * 300000)
        self.assertEqual(mock_bridge.loads('[[1]]'), [[1]])

    async def test_a_deep_frame_before_authentication_gets_bye_too_large(self):
        conn = mock_bridge.Conn(self.bridge, None, 1)
        # 600 KB: over max_request, under the 1 MB the WebSocket reads. Parsing it raised RecursionError, which ended
        # the connection's handler with a traceback and no bye.
        await self.bridge.on_text(conn, '{"t":"pair","pad":' + '[' * 300000 + ']' * 300000 + '}')
        frames = self.sent(conn)
        self.assertEqual([(f['t'], f['code']) for f in frames], [('bye', 'too_large')])
        self.assertIsNotNone(conn.closing)

    # M-2 -------------------------------------------------------------------------------------------------------------

    def test_a_setting_key_that_is_not_a_string_needs_a_proof(self):
        for key in (['permissions'], {'k': 'permissions'}, 7, None, True):
            self.assertTrue(self.bridge.needs_proof('setting', {'key': key, 'value': {}}), repr(key))
        self.assertTrue(self.bridge.needs_proof('setting', {'key': 'Permissions'}))
        self.assertTrue(self.bridge.needs_proof('setting', {'key': 'permissions '}))
        self.assertFalse(self.bridge.needs_proof('setting', {'key': 'theme'}))

    async def test_a_plain_setting_with_a_list_key_is_answered_proof_required(self):
        conn = mock_bridge.Conn(self.bridge, None, 1)
        conn.device = 'd-test'
        await self.bridge.on_req(conn, {'t': 'req', 'id': 'r1', 'method': 'setting', 'idem': 'i1',
                                        'params': {'key': ['permissions'], 'value': {'mode': 'full'}}})
        self.assertEqual([(f['id'], f['ok'], f['code']) for f in self.sent(conn)], [('r1', False, 'proof_required')])

    async def test_a_duplicated_key_is_judged_by_the_value_pebble_keeps(self):
        conn = mock_bridge.Conn(self.bridge, None, 1)
        conn.device = 'd-test'
        text = '{"t":"req","id":"r2","method":"setting","idem":"i2","params":{"key":"theme","key":"permissions",' \
               '"value":{"mode":"full","tools":{}}}}'
        await self.bridge.on_text(conn, text)
        await asyncio.sleep(0)  # on_req runs as a task
        for _ in range(20):
            if conn.queue:
                break
            await asyncio.sleep(0.01)
        self.assertEqual([(f['id'], f['code']) for f in self.sent(conn)], [('r2', 'proof_required')])


class ConformanceRowTests(unittest.TestCase):
    def test_the_review_rows_are_in_the_table(self):
        rows = conformance.Checker.ROWS
        for row in ('a setting key cannot dodge the proof (twice, not a string, respelled)',
                    'requests nested 20,000 and 300,000 deep leave the bridge serving'):
            self.assertIn(row, rows)
        with open(os.path.join(HERE, 'conformance.py')) as handle:
            source = handle.read()
        self.assertIn("'the right code with a bad signature gets bye bad_signature'", source)
        self.assertIn("('ts two minutes ahead', dict(ts=wire.now_ms() + 120000))", source)


if __name__ == '__main__':
    unittest.main()
