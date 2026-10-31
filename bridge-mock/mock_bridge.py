#!/usr/bin/env python3
"""Pebble Remote mock bridge: the reference implementation of the bridge contract, with a simulated Pebble behind it.

Contract v0.3 and proposals v0.5 and v0.6: the bridge contract, sections 3 (with 3.11) and 4,
claude-w's C1 to C7 in section 7, and the iOS side's proposals in section 6: 10:50 (folders, and opening things on the
Mac) and 15:14 (a new folder, made from the phone).
Python standard library only; the TLS identity (an ECDSA P-256 key and a self-signed certificate) is made with the
`openssl` command-line tool, and the screenshot test pattern is made a JPEG by the built-in `sips`.

    python3 -I bridge-mock/mock_bridge.py --print-pairing            # 127.0.0.1, an ephemeral port
    python3 -I bridge-mock/mock_bridge.py --lan --port 47800 --print-pairing --copy --bonjour   # for a real iPhone

stdout carries machine-readable lines (PORT=, PIN=, BID=, ENDPOINTS=, PAIRING_LINK=, and PAIRING_CODE= for each pairing
that waits for the person's confirmation, X-1); stderr carries the log, which is content-free (method names, codes,
timings; never message text, parameters, keys or the pairing link's code). The one exception is the six-digit code the
Mac and the phone both show while a pairing waits to be confirmed on the Mac ("pairing code 123456: confirm on the Mac").
Signals: SIGUSR1 opens a new pairing link (prints PAIRING_LINK= again); SIGUSR2 stops or starts the simulated Pebble.
"""

import argparse
import asyncio
import hashlib
import hmac
import inspect
import ipaddress
import json
import os
import random
import re
import shlex
import signal
import socket
import ssl
import stat
import subprocess
import sys
import threading
import time
import uuid
from collections import deque
from urllib.parse import urlsplit

sys.dont_write_bytecode = True  # no __pycache__ in the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import remote_wire as wire  # noqa: E402  (this folder's own module; -I leaves the script's folder off sys.path)

BRIDGE_VERSION = '0.6.0-mock'
PEBBLE_VERSION = '1.9.28'

# Section 3.9 limits
MAX_REQUEST = 131072          # a request frame's UTF-8 bytes (welcome.limits.max_request)
MAX_FRAME = 8388608           # the largest frame the bridge sends (welcome.limits.max_frame)
HARD_MESSAGE = 1 << 20        # above this an incoming message is not even read: close 1009
MAX_EVENT = 1 << 20           # an event frame above this is trimmed
MAX_QUEUE = 4 << 20           # backpressure: more than this queued for one phone closes its connection
RATE_BURST, RATE_PER_SECOND = 20, 10
CALL_TIMEOUT = 30.0
PAIRING_SECONDS, PAIRING_TRIES = 300, 5
IDEM_SECONDS = 600
REPLAY_EVENTS, REPLAY_SECONDS, REPLAY_HARD = 5000, 600, 100000
BATCH_SECONDS = 0.030
PROOF_WINDOW_MS = 60000
AUTH_SECONDS = 30.0
MAX_CONNECTIONS = 32          # open connections (paired or not); more get `bye` `busy`
UNLOCK_SECONDS = 900          # C1: an accepted Face ID proof lets the device act for this long (welcome.unlock_seconds)
PROOF_MEMORY_SECONDS = 120    # C2: an accepted proof is remembered this long, on every connection
MADE_FOLDER_SECONDS = wire.MADE_FOLDER_SECONDS  # v0.6: a folder this device made counts as known to it for this long
MADE_FOLDERS_KEPT = 64        # v0.6: at most this many made folders are remembered for one device
HANDSHAKES_PER_MINUTE = 10    # C6: per source address (loopback is exempt unless --limit-loopback)
SCREEN_LONG_SIDE = 2560       # C3: the long side of a screenshot is capped here
PAIR_CONFIRM_SECONDS = wire.PAIR_CONFIRM_SECONDS  # X-1: the person has this long to confirm the pairing code on the Mac
PAIR_CONFIRM_AUTO_SECONDS = 1.5  # X-1, --pair-confirm auto: the mock confirms after this, so the phone can show its code

# Section 3.7 (v0.2): PHONE_ALLOWED = ALLOWED - PHONE_EXCLUDED. ALLOWED is the main window's list in Pebble's
# src-tauri/src/main.rs, copied here (test_mock.py compares the copy with the Pebble checkout when it is present).
MAIN_WINDOW_ALLOWED = [
    'state', 'new_chat', 'get_chat', 'set_workspace', 'send', 'cancel', 'model_load', 'model_unload', 'set_model',
    'approve', 'reject', 'apps', 'attach', 'attach_url', 'attach_bytes', 'remove_source', 'delete_chat',
    'chat_rename', 'chat_search', 'setting', 'open_app', 'undo', 'model_profiles', 'model_discover', 'model_save',
    'model_save_many', 'model_select', 'model_effort', 'model_remove', 'memory_list', 'memory_save',
    'memory_delete', 'memory_clear', 'memory_candidates', 'memory_maintain', 'memory_resolve', 'memory_export',
    'extensions', 'skill_inspect', 'hook_events', 'extension_add', 'extension_import', 'extension_toggle',
    'extension_remove', 'media_artifact', 'media_download', 'plugin_package_preview', 'plugin_package_import',
    'plugin_package_install', 'plugin_package_update', 'plugin_package_history', 'plugin_package_inspect',
    'plugin_package_preview_rollback', 'plugin_package_rollback', 'connector_discover_interop',
    'connector_preview_registration', 'connector_register_client', 'connector_metadata', 'connector_discover',
    'connector_preview', 'connector_start', 'connector_status', 'connector_cancel', 'connector_save_bearer',
    'connector_save_environment', 'connector_disconnect', 'terminal_propose', 'open_url', 'chatgpt_start',
    'chatgpt_status', 'chatgpt_cancel', 'chatgpt_sign_out', 'view_stage', 'view_stop', 'artifact_get',
    'artifact_history', 'artifact_submit', 'artifact_stop', 'artifact_view_open', 'mods', 'mod_example',
    'mod_preview', 'mod_install', 'mod_toggle', 'mod_remove', 'run_list', 'run_get', 'run_activity', 'run_handoff',
    'run_compact', 'run_context_archive', 'search_stats', 'run_events', 'stream_read', 'process_list',
    'process_read', 'process_stop', 'process_inspect', 'process_dismiss', 'run_pause', 'run_resume',
    'run_held_tests', 'run_held_finish', 'run_held_accept', 'run_reconcile', 'run_readback', 'upgrade_backups',
    'upgrade_discard_backup', 'upgrade_retry', 'process_terminal', 'process_input_human', 'plan_credentials',
    'plan_credential_save', 'plan_credential_delete', 'memory_contests', 'memory_resolve_contest',
    'memory_relations', 'memory_forget_preview', 'memory_archive_export_to', 'memory_archive_preview_file',
    'memory_archive_import_file', 'model_handoff_preview', 'model_handoff_approve', 'model_handoff_start',
    'connector_save_environment_route', 'connector_send_confirm', 'research_sources', 'screen_windows',
    'screen_session_grant', 'screen_sessions', 'screen_handoff_done', 'screen_session_revoke', 'browser_status',
    'browser_start', 'browser_stop', 'browser_tabs', 'browser_open_tab', 'browser_profile_forget',
    'command_catalogue', 'run_steer', 'question_answer', 'question_cancel', 'agent_list', 'agent_get',
    'agent_steer', 'agent_cancel', 'job_list', 'job_get', 'job_preview', 'job_create', 'job_pause',
    'job_preview_resume', 'job_resume', 'job_delete', 'notification_ack', 'git_capabilities', 'git_identity',
    'git_status', 'git_diff', 'git_history', 'git_worktrees', 'git_inspect', 'git_preview_create',
    'git_create_worktree', 'git_preview_remove', 'git_remove_worktree', 'git_forget_worktree', 'git_export',
    'git_export_file', 'git_plan_propose', 'git_plan_receipts', 'git_plan_readback', 'agent_worktrees',
    'agent_worktree_retire', 'agent_worktree_reconcile', 'project_recipes', 'environment_list', 'environment_plan',
    'environment_remove', 'notification_status', 'notification_mute', 'goal_list', 'goal_get', 'goal_create',
    'goal_state', 'goal_criterion_add', 'goal_criterion_edit', 'goal_criterion_check', 'goal_criterion_review',
    'goal_step_add', 'goal_step_edit', 'goal_step_block', 'goal_blockers', 'goal_continue', 'export_preview',
    'export_render', 'export_cancel', 'export_save', 'export_list', 'export_get', 'export_discard', 'telemetry_get',
    'telemetry_set', 'telemetry_export', 'telemetry_clear', 'artifact_refresh', 'quiz_attempt', 'quiz_start',
    'quiz_save', 'quiz_submit', 'quiz_share', 'rewind_preview', 'rewind_apply', 'context_inspect',
    'context_compact', 'browser_extension_status', 'browser_extension_pause', 'browser_extension_resume',
    'browser_extension_stop', 'browser_extension_unpair', 'storage_summary', 'storage_reveal', 'storage_delete',
    'storage_set', 'storage_settings_resolve', 'storage_restore_chat', 'storage_purge_chat', 'storage_refresh',
    'storage_trash_chat', 'storage_trash_all', 'storage_purge_all', 'storage_forget_resolve',
    'storage_cleanup_legacy', 'browser_connect_status', 'browser_connect_install', 'shell_grants',
    'shell_grant_add', 'shell_grant_remove', 'shell_undo', 'toolbox_list', 'toolbox_get', 'toolbox_remove',
    'toolbox_decide', 'app_control_status', 'app_control_request', 'approve_simple', 'reject_simple',
    'toolbox_undo_remove']
PHONE_EXCLUDED = wire.PHONE_EXCLUDED  # the contract's tables live in remote_wire.py, shared with the checker
phone_excluded = wire.phone_excluded

PHONE_ALLOWED = [m for m in MAIN_WINDOW_ALLOWED if not phone_excluded(m)]
REMOTE_METHODS = list(wire.REMOTE_METHODS)
# What the simulated Pebble answers. welcome.methods offers only these (the phone hides the rest), so the real bridge's
# list is longer; test_mock.py checks that this set is exactly SimPebble.methods().
SIMULATED = {
    'state', 'get_chat', 'chat_search', 'run_list', 'run_get', 'run_activity', 'run_events', 'stream_read',
    'model_profiles', 'screen_sessions', 'toolbox_list', 'toolbox_get', 'job_list', 'job_get', 'goal_list', 'goal_get',
    'notification_status', 'command_catalogue', 'new_chat', 'send', 'cancel', 'run_steer', 'run_pause', 'run_resume',
    'reject', 'reject_simple', 'undo', 'question_answer', 'question_cancel', 'chat_rename', 'model_select',
    'model_effort', 'screen_session_revoke', 'toolbox_remove', 'toolbox_decide', 'job_pause', 'job_resume',
    'notification_ack', 'setting', 'approve', 'approve_simple', 'storage_summary', 'storage_trash_chat',
    'storage_restore_chat', 'storage_purge_chat', 'set_workspace', 'attach_bytes', 'attach_url', 'remove_source',
    'artifact_get', 'model_load', 'model_unload', 'job_preview', 'job_create', 'job_preview_resume', 'job_delete',
    'toolbox_undo_remove', 'screen_handoff_done', 'browser_status', 'browser_stop',
    # v0.5: opening things on the Mac, simulated (never opened), all elevated
    'open_url', 'open_app', 'view_stage', 'artifact_view_open', 'browser_start', 'browser_open_tab', 'quiz_share',
    'terminal_propose', 'process_terminal',
}
METHODS = [m for m in PHONE_ALLOWED if m in SIMULATED] + REMOTE_METHODS
METHOD_SET = set(METHODS)

ELEVATED_ALWAYS = wire.ELEVATED_ALWAYS  # section 3.6 (v0.2), C1's remote.unlock, and v0.5's opening methods
# Every key Pebble's setting() accepts, classified (claude-w's 3.6 addition; v0.3 item 5). 'elevated' keys can widen
# what Pebble may do without asking: Pebble's own list, backend/pebble/settings_file.py widening(). A key that is not
# here is treated as elevated (fail closed); test_mock.py fails when Pebble's setting() gains an unclassified key.
SETTING_CLASSES = {
    'permissions': 'elevated', 'git_decisions': 'elevated', 'memory_enabled': 'elevated',
    'memory_layers': 'elevated', 'notifications': 'elevated',
    'fast_replies': 'plain', 'stealth': 'plain', 'theme': 'plain', 'reduced_motion': 'plain', 'companion': 'plain',
}
ELEVATED = sorted(m for m in METHODS if m in ELEVATED_ALWAYS) + sorted(
    'setting:' + key for key, kind in SETTING_CLASSES.items() if kind == 'elevated')
UNLOCK_FREE = wire.UNLOCK_FREE  # C1's reads
READ_ONLY = wire.READ_ONLY  # v0.3 item 4: idem optional only here
# Events the windows never get, so neither does the phone (C4).
NEVER_FORWARDED = {'native_export_pdf'}

# Every sentence the bridge writes is for the person (section 4.7). None uses host, runtime, receipt, inference, capacity.
ERRORS = {
    'not_allowed': "Pebble can't do that from your iPhone. Use Pebble on your Mac for it.",
    'proof_required': 'Confirm with Face ID to do this.',
    'bad_proof': "Pebble couldn't check that Face ID confirmation. Try again.",
    'too_large': "That's too much to send at once.",
    'rate_limited': "That's a lot of requests at once. Try again in a moment.",
    'pebble_offline': "Pebble isn't running on your Mac.",
    'timeout': "Pebble didn't answer in time.",
    'bad_request': "Pebble couldn't read that request. Update Pebble Remote if this keeps happening.",
    'unlock_required': 'Unlock Pebble Remote with Face ID before Pebble acts on what you ask.',
}
PAIR_REFUSED = "Pairing wasn't confirmed on your Mac. Show a new pairing link there and try again."  # X-1
ID_REFUSED = 'Pebble Remote sent a request it could not name. Update Pebble Remote if this keeps happening.'
RETRY_KEY_REFUSED = 'Pebble Remote must send this with a retry key. Update Pebble Remote if this keeps happening.'
BYE = {
    'unknown_device': "This iPhone isn't paired with this Mac. Pair it again from Pebble's settings on the Mac.",
    'revoked': 'This iPhone was removed from Pebble on your Mac. Pair it again to keep using it.',
    'bad_signature': "This iPhone's key didn't match. Pair it again from Pebble's settings on the Mac.",
    'bad_version': "This Pebble Remote doesn't match Pebble on your Mac. Update both to the latest version.",
    'replaced': 'Pebble Remote connected again from this iPhone.',
    'busy': 'Your Mac is busy. Try again in a moment.',
    'bad_code': 'This pairing link has expired or was already used. Show a new one on your Mac.',  # v0.3 item 1
    'too_large': 'That message was too large to read, so Pebble closed the connection. Pebble Remote reconnects by '
                 'itself.',  # v0.3 item 6
}
# v0.5: a folder the Mac does not use yet is connected only when `remote.folders` would list it, and with a proof.
WORKSPACE_REFUSED = "Choose a folder from the list. Pebble Remote can't connect that one."
FOLDER_WORDS = {
    'outside': 'Pebble Remote shows folders inside your home folder only.',
    'private': 'Pebble keeps hidden and private folders off your iPhone.',
    'missing': 'Choose a folder that exists.',  # Pebble's own words for a folder that is not there (no code)
    'unreadable': "Pebble can't open that folder on your Mac.",
    # v0.6, `remote.folder_create`: a folder that could not be made (words only, no code)
    'exists': 'A folder with that name is already there.',
    'not_writable': "Pebble can't add a folder there.",
    'not_made': "Pebble couldn't make that folder on your Mac.",
}
# v0.6: the words for a name outside the rules (code `bad_request`). `private`: a name the listing would leave out (a
# protected name such as `secrets` or `*.key`), so the folder could never be shown or connected.
NAME_WORDS = {
    'empty': 'Enter a name for the folder.',
    'encoding': "That name can't be used for a folder.",
    'long': 'That name is too long. Use a shorter one.',
    'separator': "A folder name can't contain / or :.",
    'control': "A folder name can't contain line breaks or other control characters.",
    'dot': "A folder name can't start with a dot, which would make it a hidden folder.",
    'private': 'Pebble keeps folders with that name off your iPhone. Choose another name.',
}

QUIET = False
_LOG_START = time.monotonic()


def log(message):
    """Content-free log line on stderr."""
    if not QUIET:
        print(time.strftime('%H:%M:%S') + ' mock ' + message, file=sys.stderr, flush=True)


def dumps(value):
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False, allow_nan=False)


def _no_constants(name):
    raise ValueError('not JSON: ' + name)


def loads(text):
    """JSON from the phone. Nesting deeper than Python's parser follows is unreadable like any other bad JSON: its
    RecursionError is not a ValueError, and escaping it ended the connection's handler, or a request's task, without
    an answer (security review 2026-10-30, M-1)."""
    try:
        return json.loads(text, parse_constant=_no_constants)
    except RecursionError:
        raise ValueError('not JSON: nested too deeply') from None


def short(identifier):
    return (identifier or '-')[:6]


# =====================================================================================================================
# The simulated Pebble
# =====================================================================================================================

DEFECT_TEXT = "Pebble couldn't do that because of an internal error. It is recorded in Pebble's log."


class PebbleError(Exception):
    """A refusal as Pebble's backend sends it: words for the person, plus a content-free code when there is one."""

    def __init__(self, message, code=None):
        super().__init__(message)
        self.message, self.code = message, code


LOCAL_NAME_ENDINGS = ('.local', '.localhost', '.internal', '.lan', '.home', '.corp', '.intranet')


def public_host(host):
    """Whether a host name or address is public. Pebble resolves the name (sources.public_addresses) and refuses a
    private or local address; the mock does no lookups, so it refuses the names and addresses that are plainly local."""
    host = host.lower().rstrip('.')
    try:
        return ipaddress.ip_address(host).is_global
    except ValueError:
        return '.' in host and host != 'localhost' and not host.endswith(LOCAL_NAME_ENDINGS)


def public_https_url(url, refusal, too_long=None, custom_port=False):
    """sources.check_url, then its public-address rule: a public https:// URL of at most 3,000 characters, without
    credentials, controls or spaces, and without a custom port (unless `custom_port`, which App.open_url allows).
    `refusal` is the sentence Pebble gives for each route."""
    if not isinstance(url, str) or len(url) > 3000:
        raise PebbleError(too_long or refusal)
    try:
        parsed = urlsplit(url)
        port, host = parsed.port, parsed.hostname
    except ValueError:
        raise PebbleError(refusal) from None
    if parsed.scheme != 'https' or not host or parsed.username is not None or parsed.password is not None or \
            (port not in (None, 443) and not custom_port) or re.search(r'[\x00-\x20\x7f]', url):
        raise PebbleError(refusal)
    if not public_host(host):
        raise PebbleError('Only public HTTPS sources are allowed. Local and private networks are blocked.')
    return url


# backend/pebble/activity_kinds.py (the tools the simulation uses)
ACTIVITY = {'Read': 'reading', 'ReadFile': 'reading', 'ListProjectRecipes': 'reading', 'ReadGitDiff': 'reading',
            'Glob': 'searching', 'Grep': 'searching', 'SearchFiles': 'searching', 'WebSearch': 'searching',
            'Edit': 'editing', 'Write': 'editing', 'EditFile': 'editing', 'RunTests': 'testing',
            'RunCommand': 'running', 'Shell': 'running', 'StartCommand': 'running', 'SpawnAgent': 'delegating',
            'AskUserQuestion': 'thinking', 'UpdatePlan': 'thinking'}


def classify(tool, kind):
    if kind != 'working':
        return None
    if not isinstance(tool, str) or not tool:
        return 'thinking'
    return ACTIVITY.get(tool, 'working')


# backend/pebble/app.py App.tool_label (the tools the simulation uses)
def tool_label(name, args):
    return {
        'Read': 'Reading ' + args.get('file_path', ''),
        'Glob': 'Finding project files',
        'Grep': 'Searching project source',
        'SearchFiles': 'Finding relevant source',
        'Edit': 'Preparing an edit to ' + args.get('file_path', ''),
        'RunTests': 'Requesting isolated tests',
        'RunCommand': 'Reviewing terminal command',
        'WebSearch': 'Searching the web',
        'AskUserQuestion': 'Preparing a clarification form',
        'UpdatePlan': 'Updating the task plan',
        'ListProjectRecipes': 'Finding project test and build recipes',
        'ReadFile': 'Reading a file',
    }.get(name, name)


WITHHELD_APPROVAL = 'Waiting for your decision; the reply follows it'  # runner.WITHHELD['approval']
WAITING_ANSWER = 'Waiting for delegated agents or your answer'
LIVE_STATES = {'queued', 'running', 'retry_wait'}
WAITING_STATES = {'waiting_input', 'waiting_approval', 'paused'}
RESUMABLE = {'paused', 'stopped', 'interrupted', 'waiting_input', 'waiting_approval', 'budget_exhausted',
             'verification_required', 'failed'}
SIMPLE_CARDS = {'browser_grant', 'screen_grant', 'screen_raise'}
FAST = ('off', 'follow_ups', 'long_tasks', 'always')
MODES = ('ask', 'auto', 'full')
TOOL_SWITCHES = ('files', 'edits', 'tests', 'apps', 'web', 'terminal', 'plugins', 'views')
OPTIONAL_SWITCHES = {'screen': False, 'capture': True}
MEMORY_LAYERS = ('working', 'episodic', 'semantic', 'procedural', 'temporal', 'profile')
GIT_DECISIONS = ('force_push', 'delete_remote_branch', 'repository_identity', 'clean')
CATALOGUE = [  # backend/pebble/runtime_commands.py CATALOGUE (first entries)
    {'name': 'jobs', 'arguments': '', 'description': "List this conversation's schedules and waiting notifications."},
    {'name': 'git', 'arguments': '', 'description': "Show which files changed in this project's Git repository."},
    {'name': 'help', 'arguments': '', 'description': 'List the commands you can type here.'},
    {'name': 'status', 'arguments': '', 'description': 'Show how the latest task in this conversation is going.'},
    {'name': 'runs', 'arguments': '', 'description': 'List recent tasks in this conversation.'},
    {'name': 'pause', 'arguments': '', 'description': 'Pause the running task at a safe point.'},
    {'name': 'resume', 'arguments': '[run-id] [--steps N] [--seconds N]',
     'description': 'Resume a paused or stopped task, optionally with more steps or time.'},
    {'name': 'cancel', 'arguments': '', 'description': "Stop this conversation's running task."},
    {'name': 'steer', 'arguments': 'text', 'description': 'Send a follow-up to the running task.'},
]

PROJECT = '/Users/pebble/Projects/shop-web'  # simulated paths: never the person's own
GARDEN = '/Users/pebble/Projects/garden-planner'

REPLIES = [
    "Here's what I found.\n\n- The redirect after signing in reads `next` from the query string, but the login form "
    "drops it when it posts.\n- `src/auth/redirect.ts` falls back to `/home` whenever `next` is missing.\n\nKeeping "
    "`next` in a hidden field fixes it, and the fallback stays for people who open the login page directly.",
    "Sure. A quick summary:\n\n1. **Monday** had the most orders (142), mostly from the spring sale.\n2. Returns "
    "dropped to 3.1% from 4.4% last week.\n3. Average delivery time held at 2.4 days.\n\nWant me to put this in a "
    "table you can paste into the weekly report?",
    "Done thinking it through. The simplest route is to keep one list and sort it when you show it, rather than "
    "keeping two lists in step. That removes the bug where an item appears twice after an edit.",
]
LONG_REPLY = ("I'll go through the project step by step and explain each part as I go. " * 6
              + "\n\nFirst, the build: it compiles cleanly with the current settings. Second, the routes: each one "
                "has a matching handler. Third, the styles: two files repeat the same colour values, which a shared "
                "token would tidy up. That's everything I checked.")


def _now():
    return time.time()


def _hex():
    return uuid.uuid4().hex


class SimPebble:
    """A believable Pebble backend in memory: Pebble's method names, parameters, results, refusals and event payloads
    (backend/pebble/app.py, runner.py, controller.py, interaction.py, src/types.ts), with runs that stream tokens,
    progress lines with real tool names, an approval card (`command`: `npm test`), a question and settings."""

    def __init__(self, emit, speed=1.0):
        self.emit = emit
        self.speed = max(0.05, float(speed))
        self.running = True
        self.chats, self.messages, self.actions = {}, {}, {}
        self.runs, self.questions, self.plans = {}, {}, {}
        self.metrics, self.action_runs, self.message_runs = {}, {}, {}
        self.run_events, self.activity, self.reasoning = {}, {}, {}
        self.screens = {}
        self.tasks = {}
        self.pending_launches = deque()
        self.active = self.active_run = None
        self.settings = {
            'theme': 'system', 'reduced_motion': False, 'stealth': False, 'memory_enabled': True,
            'memory_layers': {layer: True for layer in MEMORY_LAYERS},
            'permissions': {'mode': 'auto', 'tools': {**{name: True for name in TOOL_SWITCHES}, **OPTIONAL_SWITCHES}},
            'companion': {'pointer': True, 'reactions': True, 'status_words': 'rotate', 'ui_guidance': True},
            'fast_replies': 'long_tasks',
            'git_decisions': {'force_push': True, 'delete_remote_branch': True, 'repository_identity': True,
                              'clean': True},
        }
        self.profiles = [
            {'id': 'chatgpt-main', 'name': 'ChatGPT', 'kind': 'chatgpt', 'context': 272000, 'budget': 272000,
             'model': 'gpt-5.5', 'connection_id': 'chatgpt-main', 'provider_name': 'ChatGPT',
             'display_name': 'GPT-5.5', 'tools': True, 'local': False},
            {'id': 'default-local', 'name': 'Qwen 3.5 (on this Mac)', 'kind': 'gguf', 'context': 8192,
             'path': '/Users/pebble/Models/qwen-3.5-instruct.gguf', 'tools': True, 'local': True},
        ]
        self.selected = 'chatgpt-main'
        self.effort = 'medium'
        self.toolbox = {
            'tools': [{'name': 'csv_column_totals', 'purpose': 'Adds up each numeric column of a CSV file',
                       'kept_by': 'pebble', 'kept_at': _now() - 86400 * 2, 'uses': 4, 'last_used': _now() - 7200,
                       'state': 'ok', 'digest': 'a41f09c2be3d7710'}],
            'pending': [{'id': _hex(), 'name': 'word_counts', 'purpose': 'Counts words per paragraph',
                         'why': 'Pebble made it for this task; keep it for later?', 'chat_id': None}],
            'removed': []}
        self.jobs = {}
        self.notifications = []
        self.notification_settings = {'enabled': True, 'replies': True, 'preview': 'title',
                                      'kinds': {'review': True, 'question': True, 'finished': True, 'problem': True},
                                      'quiet_hours': None}
        self.trashed = {}         # chat id -> {'title', 'deleted', 'origin'}: Recently deleted
        self.sources = {}         # chat id -> sources attached for the next message
        self.uploads = {}         # attach_bytes token -> {'chat', 'name', 'data'}
        self._seed()

    # -- helpers ------------------------------------------------------------------------------------------------------

    async def sleep(self, seconds):
        await asyncio.sleep(seconds / self.speed)

    def methods(self):
        return {
            'state': self.state,
            'new_chat': self.new_chat,
            'get_chat': lambda **p: self.chat(p['id']),
            'chat_search': self.chat_search,
            'chat_rename': self.chat_rename,
            'send': self.send,
            'cancel': self.stop,
            'run_steer': self.run_steer,
            'run_pause': self.run_pause,
            'run_resume': self.run_resume,
            'approve': self.approve,
            'reject': self.reject,
            'approve_simple': lambda id, action_id: self._simple_card(id, action_id) and self.approve(id, action_id),
            'reject_simple': lambda id, action_id: self._simple_card(id, action_id) and self.reject(id, action_id),
            'undo': self.undo,
            'question_answer': self.question_answer,
            'question_cancel': self.question_cancel,
            'setting': self.setting,
            'run_list': self.run_list,
            'run_get': self.run_get,
            'run_activity': self.run_activity,
            'run_events': self.run_events_read,
            'stream_read': self.stream_read,
            'model_profiles': lambda **p: [dict(p_) for p_ in self.profiles],
            'model_select': self.model_select,
            'model_effort': self.model_effort,
            'screen_sessions': lambda id: [dict(s) for s in self.screens.values() if s['chat_id'] == id],
            'screen_session_revoke': self.screen_session_revoke,
            'toolbox_list': lambda: self.toolbox_view(),
            'toolbox_get': self.toolbox_get,
            'toolbox_remove': self.toolbox_remove,
            'toolbox_decide': self.toolbox_decide,
            'job_list': self.job_list,
            'job_get': self.job_get,
            'job_pause': lambda id, job_id, revision: self._job_state(id, job_id, revision, 'paused'),
            'job_resume': self.job_resume,
            'goal_list': lambda chat_id, limit=20: {'goals': []},
            'goal_get': self.goal_get,
            'notification_status': lambda **p: {
                'settings': json.loads(json.dumps(self.notification_settings)), 'quiet_now': False,
                'outbox': {'pending': len(self.notifications)}},
            'notification_ack': self.notification_ack,
            'command_catalogue': lambda **p: CATALOGUE,
            # v0.2 P1 (section 3.7)
            'storage_summary': self.storage_summary,
            'storage_trash_chat': self.storage_trash_chat,
            'storage_restore_chat': self.storage_restore_chat,
            'storage_purge_chat': self.storage_purge_chat,
            'set_workspace': self.set_workspace,
            'attach_bytes': self.attach_bytes,
            'attach_url': self.attach_url,
            'remove_source': self.remove_source,
            'artifact_get': self.artifact_get,
            'model_load': lambda **p: self.model_status(),
            'model_unload': lambda **p: self.model_status(),
            'job_preview': self.job_preview,
            'job_create': self.job_create,
            'job_preview_resume': self.job_preview_resume,
            'job_delete': self.job_delete,
            'toolbox_undo_remove': self.toolbox_undo_remove,
            'screen_handoff_done': self.screen_handoff_done,
            'browser_status': lambda **p: {'running': False, 'profile': 'pebble', 'tabs': 0},
            'browser_stop': lambda **p: True,
            # v0.5 (proposal of 2026-10-30 10:50): opening things on the Mac, simulated and all elevated
            'open_url': self.open_url,
            'open_app': self.open_app,
            'view_stage': self.view_stage,
            'artifact_view_open': self.artifact_view_open,
            'browser_start': self.browser_start,
            'browser_open_tab': self.browser_open_tab,
            'quiz_share': self.quiz_share,
            'terminal_propose': self.terminal_propose,
            'process_terminal': self.process_terminal,
        }

    async def call(self, method, params):
        """One backend call, as main.py answers it: the result, or a refusal in words (PebbleError)."""
        function = self.methods().get(method)
        if function is None:
            raise PebbleError("Pebble can't do that from this window.")
        try:
            result = function(**params)
            if inspect.isawaitable(result):
                result = await result
        except PebbleError:
            raise
        except ValueError as exc:
            raise PebbleError(str(exc), getattr(exc, 'code', None)) from None
        except (TypeError, KeyError, AttributeError, IndexError):
            raise PebbleError(DEFECT_TEXT) from None
        return loads(dumps(result))  # a snapshot: later changes never alter an answer already given

    # -- seed: several conversations, a waiting card and a waiting question -------------------------------------------

    def _seed(self):
        now = _now()
        # 1. A finished task with an applied edit
        c1 = self._new_chat_row('Fix the login redirect', PROJECT, now - 3 * 3600)
        r1 = self._new_run(c1, 'The login page sends people to /home after signing in.', 'completed', now - 3 * 3600,
                           steps=6, elapsed=48.2)
        self._add_message(c1, 'user', 'The login page sends people to /home after signing in instead of the page '
                                      'they came from. Can you fix it?', now - 3 * 3600)
        edit = self._add_action(c1, 'edit', 'applied', {
            'root': PROJECT, 'path': 'src/auth/redirect.ts', 'permission_mode': 'auto',
            'result': {'path': 'src/auth/redirect.ts', 'hash': hashlib.sha256(b'redirect').hexdigest(),
                       'bytes': 1840}}, now - 3 * 3600 + 30, r1)
        self.action_runs[edit] = r1
        m1 = self._add_message(c1, 'assistant', REPLIES[0], now - 3 * 3600 + 48, run_id=r1)
        self.metrics[m1] = self._usage(REPLIES[0], 48.2, calls=4)
        # 2. A task waiting for an approval card: `npm test`
        c2 = self._new_chat_row('Tidy the test suite', PROJECT, now - 1800)
        r2 = self._new_run(c2, 'Run the tests and tell me what fails.', 'waiting_approval', now - 1800, steps=3,
                           elapsed=11.4)
        self._add_message(c2, 'user', 'Run the tests and tell me what fails.', now - 1800)
        m2 = self._add_message(c2, 'assistant', "I'll run the project's tests first to see what fails.",
                               now - 1790, run_id=r2)
        self.metrics[m2] = self._usage('x' * 60, 9.8, calls=2)
        card = self._add_action(c2, 'command', 'pending', self._command_payload('npm test'), now - 1789, r2)
        self.action_runs[card] = r2
        session = 'scr-' + _hex()[:12]
        self.screens[session] = {'session_id': session, 'chat_id': c2, 'run_id': None, 'kind': 'window',
                                 'target': {'app': 'Calculator', 'title': 'Calculator'},
                                 'actions': ['observe', 'press'], 'state': 'active', 'reason': None,
                                 'expires': now + 900, 'pending': True}
        # 3. A task waiting for an answer
        c3 = self._new_chat_row('Plan the garden beds', GARDEN, now - 600)
        r3 = self._new_run(c3, 'Help me plan the vegetable beds for spring.', 'waiting_input', now - 600, steps=2,
                           elapsed=7.9)
        self._add_message(c3, 'user', 'Help me plan the vegetable beds for spring.', now - 600)
        self._new_question(r3, c3, now - 590)
        self.plans[r3] = {'run_id': r3, 'revision': 1, 'updated': now - 595, 'steps': [
            {'id': 'beds', 'title': 'Choose which beds to plan first', 'status': 'in_progress', 'evidence_ids': []},
            {'id': 'crops', 'title': 'Match crops to sun and soil', 'status': 'pending', 'evidence_ids': []},
            {'id': 'calendar', 'title': 'Write the sowing calendar', 'status': 'pending', 'evidence_ids': []}]}
        # 4. An older plain conversation
        c4 = self._new_chat_row('Weekly numbers', None, now - 86400)
        r4 = self._new_run(c4, 'Summarise this week’s numbers.', 'completed', now - 86400, steps=1, elapsed=6.1)
        self._add_message(c4, 'user', 'Summarise this week’s order numbers for the report.', now - 86400)
        m4 = self._add_message(c4, 'assistant', REPLIES[1], now - 86400 + 6, run_id=r4)
        self.metrics[m4] = self._usage(REPLIES[1], 6.1)
        self.jobs[c4] = [{'id': 'job-' + _hex()[:10], 'name': 'Weekly numbers', 'task': 'Summarise the week',
                          'schedule': {'kind': 'daily', 'time': '09:00', 'timezone': 'Europe/London'},
                          'state': 'active', 'revision': 3, 'next_fire': int(now + 86400), 'error': None,
                          'last_run_id': r4, 'last_run_state': 'completed', 'monitor': False,
                          'config': {'effort': 'medium'}},
                         {'id': 'job-' + _hex()[:10], 'name': 'Check the shop for broken links', 'task': 'Check links',
                          'schedule': {'kind': 'interval', 'seconds': 21600}, 'state': 'paused', 'revision': 2,
                          'next_fire': None, 'error': None, 'last_run_id': None, 'last_run_state': None,
                          'monitor': True, 'config': {'effort': 'low'}}]

    def _new_chat_row(self, title, workspace, updated):
        cid = _hex()
        self.chats[cid] = {'id': cid, 'title': title, 'workspace': workspace, 'updated': updated}
        self.messages[cid], self.actions[cid] = [], []
        return cid

    def _new_run(self, cid, goal, state, created, steps=0, elapsed=0.0):
        rid = _hex()
        self.runs[rid] = {'id': rid, 'chat_id': cid, 'state': state, 'steps': steps, 'elapsed': elapsed,
                          'error': None, 'created': created, 'updated': created, 'goal': goal, 'steer': [],
                          'pause': False, 'continuation': None}
        self.run_events[rid] = []
        self.activity[rid] = []
        return rid

    def _add_message(self, cid, role, content, created=None, run_id=None, mid=None):
        mid = mid or _hex()
        created = created if created is not None else _now()
        self.messages[cid].append({'id': mid, 'chat_id': cid, 'role': role, 'content': content, 'created': created})
        if run_id:
            self.message_runs[mid] = run_id
        self.chats[cid]['updated'] = max(self.chats[cid]['updated'] or 0, created)
        if role == 'user' and self.chats[cid]['title'] == 'New conversation':
            self.chats[cid]['title'] = content[:54].replace('\n', ' ')
        return mid

    def _add_action(self, cid, kind, status, payload, created=None, run_id=None):
        aid = _hex()
        self.actions[cid].append({'id': aid, 'chat_id': cid, 'kind': kind, 'status': status, 'payload': payload,
                                  'created': created if created is not None else _now()})
        if run_id:
            self.action_runs[aid] = run_id
        return aid

    def _new_question(self, rid, cid, created=None):
        qid = _hex()
        self.questions[qid] = {
            'id': qid, 'run_id': rid, 'call_id': 'call_' + _hex()[:12], 'revision': 1, 'required': True,
            'status': 'pending', 'created': created if created is not None else _now(), 'answered': None,
            'answer': None, 'chat_id': cid,
            'items': [{'id': 'beds', 'title': 'Which beds should I plan first?', 'allow_free_text': True,
                       'options': [{'id': 'front', 'label': 'The front beds', 'description': 'Morning sun, near the tap'},
                                   {'id': 'back', 'label': 'The back beds', 'description': 'Sun after noon'}]}]}
        return qid

    @staticmethod
    def _command_payload(command):
        """A RunCommand card's payload (terminal.inspect_command + App.propose)."""
        return {'root': PROJECT, 'root_identity': [16777232, 48123011], 'command': command,
                'argv': command.split(), 'network': False, 'risk': 'execution', 'requires_review': True,
                'writable': True, 'planned': False, 'permission_mode': 'ask'}

    @staticmethod
    def _usage(text, seconds, calls=1):
        output = max(1, len(text) // 4)
        reported = {'input': 5200 + 900 * calls, 'cached': 3900 + 700 * calls, 'output': output, 'reasoning': 120,
                    'tokens_per_second': 61.5, 'attempts': calls, 'generation_seconds': round(seconds * 0.6, 2)}
        return {'input_tokens': reported['input'], 'output_tokens': output, 'cached_tokens': reported['cached'],
                'tokens_per_second': 61.5, 'calls': calls, 'generation_seconds': reported['generation_seconds'],
                'route': 'model', 'seconds': round(seconds, 1), 'reported': reported}

    def known_workspaces(self):
        return {row['workspace'] for row in self.chats.values() if row['workspace']}

    def _chat_row(self, cid):
        row = self.chats.get(cid)
        if row is None:
            raise PebbleError('Conversation not found.')
        return row

    def _run_rows(self, cid=None):
        rows = [r for r in self.runs.values() if cid is None or r['chat_id'] == cid]
        rows.sort(key=lambda r: r['created'], reverse=True)
        keys = ('id', 'chat_id', 'state', 'steps', 'elapsed', 'error', 'created', 'updated')
        return [{k: r[k] for k in keys} for r in rows[:100]]

    def _question_view(self, q):
        return {k: q[k] for k in ('id', 'run_id', 'call_id', 'revision', 'required', 'status', 'items', 'answer',
                                  'created', 'answered', 'chat_id')}

    # -- reading ------------------------------------------------------------------------------------------------------

    def state(self):
        listed = [dict(row) for cid, row in self.chats.items()
                  if (self.messages[cid] or self.actions[cid]) and cid not in self.trashed]
        listed.sort(key=lambda row: row['updated'] or 0, reverse=True)
        return {
            'job_notifications': [dict(n) for n in self.notifications],
            'chats': listed,
            'model': self.model_status(),
            'guard': {'available': True, 'error': None},
            'active': self.active,
            'active_run': self.active_run,
            'runs': self._run_rows(),
            'settings': json.loads(json.dumps(self.settings)),
            'data_dir': '/Users/pebble/.pebble',
            'platform': 'darwin',
            'version': PEBBLE_VERSION,
            'memory': {'enabled': self.settings['memory_enabled'],
                       'strategy': 'SQLite FTS5 · hybrid lexical/trigram/metadata ranking · bounded retrieval',
                       'types': [{'id': layer, 'name': layer.title(), 'count': 3, 'enabled': True}
                                 for layer in MEMORY_LAYERS]},
            'profiles': [dict(p) for p in self.profiles],
        }

    def model_status(self):
        profile = next(p for p in self.profiles if p['id'] == self.selected)
        local = profile['kind'] == 'gguf'
        return {'state': 'ready', 'configured': True, 'name': profile.get('display_name') or profile['name'],
                'path': profile.get('path', ''), 'context': profile['context'],
                'budget': profile.get('budget', profile['context']), 'protocol': 'responses' if not local else 'gguf',
                'efforts': ['low', 'medium', 'high'], 'effort': self.effort, 'default_effort': 'medium',
                'kind': profile['kind'], 'local': local, 'provider': 'ChatGPT' if not local else 'This Mac',
                'profile_id': profile['id']}

    def chat(self, cid):
        row = self._chat_row(cid)
        actions = [dict(a) for a in self.actions[cid]]
        messages = []
        for message in sorted(self.messages[cid], key=lambda m: m['created']):
            item = {'attachments': [], **message}
            if message['id'] in self.metrics:
                item['usage'] = self.metrics[message['id']]
            if message['role'] == 'assistant' and message['id'] in self.message_runs:
                item['run_id'] = self.message_runs[message['id']]
            messages.append(item)
        runs = self._run_rows(cid)
        for run in runs[:20]:
            if run['state'] not in LIVE_STATES:
                run['counts'] = {'steps': run['steps'], 'retries': 0, 'waited': 0}
        questions = [self._question_view(q) for q in self.questions.values()
                     if q['chat_id'] == cid and q['status'] == 'pending']
        question_runs = {q['run_id'] for q in questions}
        focused = next((r for r in runs if r['state'] in LIVE_STATES), None)
        focused = focused or next((r for r in runs if r['id'] in question_runs), None)
        focused = focused or next((r for r in runs if r['state'] == 'waiting_approval'), None)
        focused = focused or (runs[0] if runs else None)
        return {**row, 'trashed': cid in self.trashed, 'messages': messages, 'actions': actions, 'artifacts': [], 'runs': runs,
                'questions': questions, 'plan': self.plans.get(focused['id']) if focused else None}

    def chat_search(self, query=''):
        words = ' '.join(str(query or '').split())[:200]
        if len(words) < 2:
            return {'query': words, 'matches': []}
        matches = []
        for cid in sorted(self.chats, key=lambda c: self.chats[c]['updated'] or 0, reverse=True):
            hits = [m for m in self.messages[cid] if words.lower() in m['content'].lower()]
            if hits:
                text = ' '.join(re.sub(r'[*_`#>]+', '', hits[-1]['content']).split())
                at = max(0, text.lower().find(words.lower()))
                start = max(0, at - 40)
                matches.append({'id': cid, 'excerpt': ('…' if start else '') + text[start:start + 120]
                                + ('…' if start + 120 < len(text) else '')})
        return {'query': words, 'matches': matches[:30]}

    def run_list(self, id):
        self._chat_row(id)
        return self._run_rows(id)

    def run_get(self, id, run_id):
        run = self.runs.get(run_id)
        if not run or run['chat_id'] != id:
            raise PebbleError('Run not found in this conversation.')
        keys = ('id', 'chat_id', 'state', 'steps', 'elapsed', 'error', 'created', 'updated', 'goal')
        return {**{k: run[k] for k in keys}, 'config': {'effort': self.effort, 'limits': {'max_steps': 60,
                                                                                         'max_seconds': 1800}},
                'checkpoint': None}

    def run_activity(self, run_id, after=0):
        if type(after) is not int or after < 0:
            raise PebbleError('Use a nonnegative whole activity cursor.')
        run = self.runs.get(run_id)
        if run is None:
            raise PebbleError('Run not found.')
        items = [i for i in self.activity.get(run_id, []) if i['seq'] > after or i['status'] == 'running'][:200]
        text = self.reasoning.get(run_id, '')
        return {'run_id': run_id, 'state': run['state'], 'started': run['created'], 'elapsed': round(run['elapsed'], 3),
                'items': items, 'reasoning': {'available': bool(text), 'text': text}, 'usage': None,
                'next': max([after] + [i['seq'] for i in items])}

    def run_events_read(self, id, run_id, after=0, limit=100):
        run = self.runs.get(run_id)
        if not run or run['chat_id'] != id:
            raise PebbleError('Run not found in this conversation.')
        if type(after) is not int or after < 0 or type(limit) is not int or not 1 <= limit <= 200:
            raise PebbleError('Use a nonnegative event cursor and a limit from 1 to 200.')
        return [e for e in self.run_events[run_id] if e['sequence'] > after][:limit]

    def stream_read(self, id, run_id, after=0, limit=50):
        run = self.runs.get(run_id)
        if not run or run['chat_id'] != id:
            raise PebbleError('Run not found in this conversation.')
        return {'chat_id': id, 'run_id': run_id, 'after': after, 'events': [], 'next_after': after, 'more': False,
                'head': after, 'presentation_only': True,
                'notice': 'Display copy of the streamed reply; the saved conversation is the record.'}

    def toolbox_get(self, name):
        tool = next((t for t in self.toolbox['tools'] if t['name'] == name), None)
        if tool is None:
            raise PebbleError('That tool is not in your Toolbox.')
        return {**tool, 'code': 'def run(path):\n    ...\n', 'inputs': {'path': 'a CSV file'}, 'tests': 3}

    def toolbox_remove(self, name):
        """backend/pebble/workshop.py remove(): the tool can be put back for ten minutes; answers the listing."""
        tool = next((t for t in self.toolbox['tools'] if t['name'] == name), None)
        if tool is None:
            raise PebbleError('No kept tool has that name.')
        self.toolbox['tools'].remove(tool)
        self.toolbox['removed'].append({'name': name, 'purpose': tool['purpose'], 'seconds_left': 600, '_tool': tool})
        self.emit('toolbox', {'kind': 'remove', 'name': name})
        return self.toolbox_view()

    def toolbox_undo_remove(self, name):
        entry = next((r for r in self.toolbox['removed'] if r['name'] == name), None)
        if entry is None:
            raise PebbleError('That tool can no longer be put back (after ten minutes it is gone for good).')
        if any(t['name'] == name for t in self.toolbox['tools']):
            raise PebbleError('A tool with that name is in the Toolbox again.')
        self.toolbox['removed'].remove(entry)
        self.toolbox['tools'].append(entry['_tool'])
        self.emit('toolbox', {'kind': 'restore', 'name': name})
        return self.toolbox_view()

    def toolbox_view(self):
        """The listing as Pebble answers it (workshop.listing): tools, pending decisions, removed ones."""
        return {'tools': [dict(t) for t in self.toolbox['tools']], 'pending': [dict(p) for p in self.toolbox['pending']],
                'removed': [{k: v for k, v in r.items() if k != '_tool'} for r in self.toolbox['removed']]}

    def toolbox_decide(self, pending_id, keep):
        item = next((p for p in self.toolbox['pending'] if p['id'] == pending_id), None)
        if item is None:
            raise PebbleError('That request is no longer waiting.')
        if type(keep) is not bool:
            raise PebbleError('Choose keep or discard.')
        self.toolbox['pending'].remove(item)
        if keep:
            self.toolbox['tools'].append({'name': item['name'], 'purpose': item['purpose'], 'kept_by': 'person',
                                          'kept_at': _now(), 'uses': 0, 'last_used': None, 'state': 'ok',
                                          'digest': _hex()[:16]})
        self.emit('toolbox', {'kind': 'keep' if keep else 'discard', 'name': item['name']})
        return self.toolbox_view()

    def job_list(self, id):
        self._chat_row(id)
        return {'jobs': [dict(j) for j in self.jobs.get(id, [])], 'notifications': [],
                'service': {'running': True, 'execution': 'while_service_running', 'last_error': None}}

    def job_get(self, id, job_id):
        return {'job': dict(self._job(id, job_id)), 'fires': [], 'drift': None}

    def _job(self, id, job_id):
        self._chat_row(id)
        job = next((j for j in self.jobs.get(id, []) if j['id'] == job_id), None)
        if job is None:
            raise PebbleError('Schedule not found in this conversation.')
        return job

    def _fingerprint(self, *parts):
        """job_api's config_fingerprint: a digest of what the schedule would run with (here: model, effort, mode)."""
        pin = dumps([self.selected, self.effort, self.settings['permissions']['mode'], *parts])
        return hashlib.sha256(pin.encode()).hexdigest()

    def _job_config(self, effort=None):
        return {'model': self.model_status()['name'], 'effort': effort or self.effort,
                'mode': self.settings['permissions']['mode']}

    @staticmethod
    def _schedule(schedule):
        kinds = {'once': {'kind', 'at'}, 'interval': {'kind', 'seconds'}, 'daily': {'kind', 'time', 'timezone'}}
        if not isinstance(schedule, dict) or schedule.get('kind') not in kinds or \
                not kinds[schedule['kind']] <= set(schedule):
            raise PebbleError('Choose once (at), an interval (seconds) or daily (time, timezone).')
        return dict(schedule)

    def _next_times(self, schedule, count=3):
        now = int(_now())
        if schedule['kind'] == 'once':
            return [int(schedule['at'])]
        step = int(schedule['seconds']) if schedule['kind'] == 'interval' else 86400
        return [now + step * (n + 1) for n in range(count)]

    def job_preview(self, id, schedule, limits, effort=None):
        self._chat_row(id)
        schedule = self._schedule(schedule)
        return {'config_fingerprint': self._fingerprint(effort), 'config': self._job_config(effort),
                'schedule': schedule, 'next_times': self._next_times(schedule)}

    def job_create(self, id, name, task, schedule, monitor, limits, config_fingerprint, effort=None):
        self._chat_row(id)
        schedule = self._schedule(schedule)
        if config_fingerprint != self._fingerprint(effort):
            raise PebbleError('Preview the job and pass its config_fingerprint.')
        if not isinstance(name, str) or not name.strip() or not isinstance(task, str) or not task.strip():
            raise PebbleError('Name the schedule and say what Pebble should do.')
        job = {'id': 'job-' + _hex()[:10], 'name': name.strip()[:80], 'task': task.strip(), 'schedule': schedule,
               'state': 'active', 'revision': 1, 'next_fire': self._next_times(schedule, 1)[0], 'error': None,
               'last_run_id': None, 'last_run_state': None, 'monitor': bool(monitor), 'config': self._job_config(effort)}
        self.jobs.setdefault(id, []).append(job)
        self.emit('job', {'chat_id': id, 'job_id': job['id'], 'state': 'active'})
        return dict(job)

    def _job_state(self, id, job_id, revision, state):
        job = self._job(id, job_id)
        if type(revision) is not int or revision != job['revision']:
            raise PebbleError('This schedule changed. Refresh it and try again.')
        job.update(state=state, revision=job['revision'] + 1)
        self.emit('job', {'chat_id': id, 'job_id': job_id, 'state': state})
        return dict(job)

    def job_preview_resume(self, id, job_id, revision):
        job = self._job(id, job_id)
        if type(revision) is not int or revision != job['revision']:
            raise PebbleError('This schedule changed. Refresh it and try again.')
        if job['state'] not in ('paused', 'needs_review'):
            raise PebbleError('Only a paused job or one awaiting review can be resumed.')
        return {'config_fingerprint': self._fingerprint(job['config'].get('effort')), 'config': self._job_config()}

    def job_resume(self, id, job_id, revision, config_fingerprint):
        job = self._job(id, job_id)
        if job['state'] not in ('paused', 'needs_review'):
            raise PebbleError('Only a paused job or one awaiting review can be resumed.')
        if config_fingerprint != self._fingerprint(job['config'].get('effort')):
            raise PebbleError('Preview the job and pass its config_fingerprint.')
        return self._job_state(id, job_id, revision, 'active')

    def job_delete(self, id, job_id, revision):
        job = self._job(id, job_id)
        if type(revision) is not int or revision != job['revision']:
            raise PebbleError('This schedule changed. Refresh it and try again.')
        self.jobs[id].remove(job)
        self.emit('job', {'chat_id': id, 'job_id': job_id, 'state': 'deleted'})
        return {'deleted': job_id}

    # -- Recently deleted, projects, attachments (v0.2 P1) -------------------------------------------------------------

    def storage_summary(self):
        """data_mirror.summary(), with the parts the phone reads; `recently_deleted` newest first."""
        rows = [{'chat_id': cid, 'title': e['title'], 'deleted': e['deleted'], 'origin': e['origin'],
                 'delete_after': e['deleted'] + 30 * 86400}
                for cid, e in sorted(self.trashed.items(), key=lambda kv: -kv[1]['deleted'])]
        return {'available': True, 'home': {'path': '/Users/pebble/.pebble', 'default': True},
                'documents': {'enabled': False, 'reason': None}, 'categories': [], 'recently_deleted': rows[:200],
                'events': [], 'problems': []}

    def storage_trash_chat(self, chat_id):
        row = self._chat_row(chat_id)
        if chat_id in self.trashed:
            raise PebbleError('That conversation is already in Recently deleted.')
        if self.active == chat_id:
            raise PebbleError('Stop the current task before deleting this conversation.')
        self.trashed[chat_id] = {'title': row['title'], 'deleted': _now(), 'origin': 'remote'}
        self.emit('storage', {'changed': 'recently_deleted', 'chat_id': chat_id})
        return {'trashed': chat_id, 'delete_after': self.trashed[chat_id]['deleted'] + 30 * 86400}

    def storage_restore_chat(self, chat_id):
        self._chat_row(chat_id)
        if chat_id not in self.trashed:
            raise PebbleError('That conversation is not in Recently deleted.')
        del self.trashed[chat_id]
        self.emit('storage', {'changed': 'recently_deleted', 'chat_id': chat_id})
        return {'restored': chat_id}

    def storage_purge_chat(self, chat_id, confirm=False):
        if confirm is not True:
            raise PebbleError('Confirm the deletion first.')
        if chat_id not in self.trashed:
            raise PebbleError('That conversation is not in Recently deleted.')
        del self.trashed[chat_id]
        for store in (self.chats, self.messages, self.actions, self.sources):
            store.pop(chat_id, None)
        for rid in [r for r, run in self.runs.items() if run['chat_id'] == chat_id]:
            del self.runs[rid]
        for qid in [q for q, item in self.questions.items() if item['chat_id'] == chat_id]:
            del self.questions[qid]
        self.emit('storage', {'changed': 'recently_deleted', 'chat_id': chat_id})
        return {'deleted': chat_id}

    def workspace_root(self, path):
        """Pebble's Workspace(path).root: none (the Companion), a project a conversation already uses, or a folder that
        exists, resolved. What the phone may ask for is the bridge's rule (Bridge.policy); this is Pebble's own check."""
        if path is None or path == '':
            return None
        if not isinstance(path, str):
            raise PebbleError('Choose a folder that exists.')
        if path in self.known_workspaces():
            return path
        if not os.path.isdir(path):
            raise PebbleError('Choose a folder that exists.')
        return os.path.realpath(path)

    def set_workspace(self, id, path):
        if self.active or self.pending_launches:
            raise PebbleError('Stop the current task before changing its project.')
        row = self._chat_row(id)
        row['workspace'] = self.workspace_root(path)
        return self.chat(id)

    def attach_bytes(self, id, name, data_base64, upload=None, offset=0, final=True):
        """attachments.attach_bytes: base64 pieces of at most 96,000 characters, each at the byte offset received so
        far; a piece that is not the last answers {upload, received}; the last answers the attachment."""
        self._chat_row(id)
        if not isinstance(data_base64, str) or len(data_base64) > 96000:
            raise PebbleError('Send pasted data in base64 chunks of at most 96,000 characters.')
        if type(offset) is not int or offset < 0 or type(final) is not bool:
            raise PebbleError('Choose a non-negative byte offset and a final flag.')
        try:
            chunk = __import__('base64').b64decode(data_base64, validate=True)
        except ValueError:
            raise PebbleError('The pasted data is not valid base64.') from None
        if upload is None:
            if len(self.sources.get(id, [])) >= 10:
                raise PebbleError('Use up to ten attachments per message.')
            upload = 'up-' + _hex()[:16]
            self.uploads[upload] = {'chat': id, 'name': str(name or 'Pasted file')[:120], 'data': bytearray()}
        state = self.uploads.get(upload)
        if state is None or state['chat'] != id:
            raise PebbleError('This paste is no longer in progress. Paste again.')
        if offset != len(state['data']):
            del self.uploads[upload]
            raise PebbleError('This paste is no longer in progress. Paste again.')
        if len(state['data']) + len(chunk) > 20 * 1024 * 1024:
            del self.uploads[upload]
            raise PebbleError('Attach a file of at most 20 MB.')
        state['data'] += chunk
        if not final:
            return {'upload': upload, 'received': len(state['data'])}
        del self.uploads[upload]
        data = bytes(state['data'])
        image = data[:3] == b'\xff\xd8\xff' or data[:8] == b'\x89PNG\r\n\x1a\n'
        source = {'id': _hex(), 'name': state['name'], 'kind': 'image' if image else 'file', 'bytes': len(data)}
        if not image:
            source['characters'] = len(data.decode('utf-8', 'replace'))
        self.sources.setdefault(id, []).append(source)
        return dict(source)

    def attach_url(self, id, url):
        """App.attach_url, in Pebble's order: the web switch, the conversation, the address (sources.check_url and
        its public-address rule), then up to ten sources per message. The fetch is simulated: nothing leaves this
        Mac, and the source always has 2,400 characters."""
        if not self.settings['permissions']['tools']['web']:
            raise PebbleError('Web access is disabled in Permissions.')
        self._chat_row(id)
        public_https_url(url, 'Enter a public https:// URL without credentials or a custom port.',
                         'Use a public URL shorter than 3,000 characters.')
        if len(self.sources.get(id, [])) >= 10:
            raise PebbleError('Use up to ten sources per message.')
        source = {'id': _hex(), 'name': url, 'kind': 'url', 'characters': 2400}
        self.sources.setdefault(id, []).append(source)
        return {'id': source['id'], 'name': source['name'], 'characters': source['characters']}

    def remove_source(self, id, source_id):
        self.sources[id] = [s for s in self.sources.get(id, []) if s['id'] != source_id]
        return True

    def artifact_get(self, chat_id, id, revision=None):
        self._chat_row(chat_id)
        raise PebbleError('Artifact not found in this conversation.')

    def screen_handoff_done(self, session_id):
        session = self.screens.get(session_id)
        if session is None or session['state'] == 'revoked':
            raise PebbleError('That window is no longer shared.')
        session['state'] = 'active'
        return {'session_id': session_id, 'state': 'active', 'fresh_observation_required': True}

    def goal_get(self, chat_id, goal_id):
        self._chat_row(chat_id)
        raise PebbleError('Goal not found in this conversation.')

    def notification_ack(self, id, notification_id):
        before = len(self.notifications)
        self.notifications = [n for n in self.notifications if n['id'] != notification_id]
        return {'acknowledged': before - len(self.notifications)}

    # -- acting -------------------------------------------------------------------------------------------------------

    def new_chat(self, workspace=None):
        """Keeps the workspace as the conversation's project (Pebble stores the folder resolved)."""
        cid = self._new_chat_row('New conversation', self.workspace_root(workspace), _now())
        return self.chat(cid)

    # -- opening things on the Mac (proposal v0.5): the mock opens nothing -----------------------------------------------

    @staticmethod
    def _would_open(what):
        """Every one of these is elevated (the bridge asked for a proof before this runs). The simulated Pebble never
        opens anything on this Mac: it says what it would open in the log (content-free) and answers ok."""
        log('simulated Pebble would open %s on the Mac; nothing was opened' % what)
        return {'ok': True}

    def open_url(self, url):
        public_https_url(url, 'Only public HTTPS links can be opened.', custom_port=True)
        return self._would_open('a web page')

    def open_app(self, id, app_id):
        self._chat_row(id)
        if not isinstance(app_id, str) or not app_id.strip():
            raise PebbleError('Select an installed app.')
        return self._would_open('an app')

    def view_stage(self, **params):
        return self._would_open('a view')

    def artifact_view_open(self, chat_id, id, revision):
        self._chat_row(chat_id)
        if not isinstance(id, str) or not id or type(revision) is not int:
            raise PebbleError('Open the current active HTML revision for native review.')
        return self._would_open('an artifact')

    def browser_start(self, **params):
        return self._would_open("Pebble's browser")

    def browser_open_tab(self, url):
        """browser_session.open_tab: an https address, or an http address on this Mac (loopback), that the person typed."""
        try:
            parsed = urlsplit(url) if isinstance(url, str) and len(url) <= 3000 else None
            host = parsed.hostname if parsed else None
        except ValueError:
            parsed = host = None
        local = host in ('localhost', '127.0.0.1', '::1')
        if url != 'about:blank' and (parsed is None or not host or parsed.username is not None or
                                     parsed.password is not None or
                                     not (parsed.scheme == 'https' or (parsed.scheme == 'http' and local))):
            raise PebbleError('Open an https address, or an http address on this Mac.')
        return self._would_open('a browser tab')

    def quiz_share(self, chat_id, attempt_id, surface=None):
        self._chat_row(chat_id)
        if not isinstance(attempt_id, str) or not attempt_id:
            raise PebbleError('Quiz attempt not found.')
        return self._would_open('a quiz result')

    def process_terminal(self, id, run_id, process_id):
        self._chat_row(id)
        run = self.runs.get(run_id)
        if not run or run['chat_id'] != id:
            raise PebbleError('Run not found in this conversation.')
        if not isinstance(process_id, str) or not process_id:
            raise PebbleError('Process not found in this run.')
        return self._would_open("a process's terminal")

    def terminal_propose(self, id, command, network=False):
        """The composer's "Terminal command": Pebble's review card for the command, as the main window makes it (app.py
        terminal_propose, then propose). Nothing runs until the card is approved, and the mock never runs a command:
        the approval answers a simulated result."""
        row = self._chat_row(id)
        if self.active:
            raise PebbleError('Wait for the current task before starting a terminal command.')
        if not row['workspace']:
            raise PebbleError('Select a project folder first.')
        argv = self._inspect_command(command, network)
        payload = self._command_payload(command)
        payload.update(root=row['workspace'], argv=argv, network=network)
        card = self._add_action(id, 'command', 'pending', payload)
        self.chats[id]['updated'] = _now()
        self.emit('actions', {'chat_id': id, 'actions': [dict(a) for a in self.actions[id]]})
        return {'status': 'awaiting_user_approval', 'action_id': card, 'kind': 'command'}

    @staticmethod
    def _inspect_command(command, network):
        """terminal.inspect_command's checks, with its words: one plain command at a time."""
        if (not isinstance(command, str) or not command.strip() or len(command) > 4000 or type(network) is not bool
                or any(c in command for c in '\n\r\x00')):
            raise PebbleError('Enter a single command shorter than 4000 characters.')
        if re.search(r'\$\(|`|\$\{', command):
            raise PebbleError('Command substitutions and environment overrides are blocked.')
        try:
            lexer = shlex.shlex(command, posix=True, punctuation_chars=';&|<>')
            lexer.whitespace_split = True
            lexer.commenters = ''
            argv = list(lexer)
        except ValueError:
            raise PebbleError("Check the command's quoting.") from None
        if not argv or any(re.fullmatch(r'[;&|<>]+', word) for word in argv):
            raise PebbleError('Run one command at a time. Pipes, redirections and chained shell commands are blocked.')
        return argv

    def chat_rename(self, id, title):
        if not isinstance(title, str) or not ' '.join(title.split()):
            raise PebbleError('Enter a name for the conversation.')
        row = self._chat_row(id)
        row['title'] = ' '.join(title.split())[:200]
        return {'id': id, 'title': row['title']}

    def send(self, id, text, deliberate=None, source_ids=None, effort=None, limits=None, watchdog=None):
        if not isinstance(text, str) or not text.strip() or len(text.encode()) > 100000:
            raise PebbleError('Enter a message under 100 KB.')
        self._chat_row(id)
        if id in self.trashed:  # data_mirror.TrashedConversation, whose code main.py passes on
            raise PebbleError('This conversation is in Recently deleted. Restore it in Settings -> Data & storage to '
                              'keep using it.', 'trashed_conversation')
        if source_ids and (self.active or text.strip().startswith('/')):
            raise PebbleError('Follow-up input during a run accepts text only. Attach sources to a new task.')
        if text.strip().startswith('/'):
            mid = self._add_message(id, 'user', text.strip(), mid='cmd-' + _hex())
            answer = 'Commands you can type here:\n\n' + '\n'.join(
                '- `/' + c['name'] + (' ' + c['arguments'] if c['arguments'] else '') + '`: ' + c['description']
                for c in CATALOGUE)
            reply = self._add_message(id, 'assistant', answer, mid='cmd-' + _hex())
            self.emit('complete', {'chat_id': id, 'id': reply, 'seconds': 0})
            return {'message_id': mid, 'command': True}
        if self.active:
            if self.active == id and self.active_run:
                result = self._steer(self.active_run, text)
                mid = self._add_message(id, 'user', text.strip())
                return {'message_id': mid, **result, 'steering': True}
            raise PebbleError('One task can run at a time on this device.')
        rid = self._new_run(id, text.strip(), 'queued', _now())
        mid = self._add_message(id, 'user', text.strip())
        chosen = [s for s in self.sources.get(id, []) if s['id'] in (source_ids or [])]
        if chosen:
            self.messages[id][-1]['attachments'] = [dict(s) for s in chosen]
        self.sources.pop(id, None)  # Pebble keeps only the chosen sources, bound to this message
        self._launch(rid, 'start')
        return {'message_id': mid, 'run_id': rid}

    def stop(self, id=None, run_id=None):
        if id and self.active and self.active != id:
            raise PebbleError('Another conversation owns the active worker.')
        if not self.active and id:
            waiting = [r for r in self._run_rows(id) if r['state'] in WAITING_STATES and (not run_id or run_id == r['id'])]
            if waiting:
                self._transition(waiting[0]['id'], 'stopped')
                self.emit('run', {'chat_id': id, 'run_id': waiting[0]['id'], 'state': 'stopped'})
                return True
        if run_id and self.active_run != run_id:
            raise PebbleError('This run is not active.')
        task = self.tasks.get(self.active_run) if self.active_run else None
        if task is not None and not task.done():
            self.runs[self.active_run]['pause'] = False
            task.cancel()
        return True

    def run_pause(self, id, run_id=None):
        if self.active != id or not self.active_run:
            candidates = [r for r in self._run_rows(id) if r['state'] in {'waiting_input', 'waiting_approval'}
                          and (not run_id or r['id'] == run_id)]
            if not candidates:
                raise PebbleError('This conversation has no active or waiting run.')
            rid = candidates[0]['id']
            self._transition(rid, 'paused')
            self.emit('run', {'chat_id': id, 'run_id': rid, 'state': 'paused'})
            return {'run_id': rid, 'status': 'paused'}
        if run_id and run_id != self.active_run:
            raise PebbleError('This run does not own the active worker.')
        rid = self.active_run
        task = self.tasks.get(rid)
        if task is not None and not task.done():
            self.runs[rid]['pause'] = True
            task.cancel()
        return {'run_id': rid, 'status': 'pause_requested'}

    def run_resume(self, id, run_id=None, limits=None, automatic=False):
        if self.active:
            raise PebbleError('Stop the active run before resuming another one.')
        self._chat_row(id)
        if run_id is None:
            candidates = [r for r in self._run_rows(id) if r['state'] in RESUMABLE]
            if not candidates:
                raise PebbleError('This conversation has no resumable run.')
            run_id = candidates[0]['id']
        run = self.runs.get(run_id)
        if not run or run['chat_id'] != id:
            raise PebbleError('Run not found in this conversation.')
        if run['state'] not in RESUMABLE:
            raise PebbleError('This run cannot be resumed.')
        if any(a['status'] in ('pending', 'running') and self.action_runs.get(a['id']) == run_id
               for a in self.actions[id]):
            raise PebbleError("Resolve this run's pending actions before resuming it.")
        if any(q['run_id'] == run_id and q['status'] == 'pending' and q['required'] for q in self.questions.values()):
            if run['state'] == 'waiting_input':
                raise PebbleError("Answer or cancel this run's required question first.")
            self._transition(run_id, 'waiting_input')
            self.emit('run', {'chat_id': id, 'run_id': run_id, 'state': 'waiting_input'})
            return {'run_id': run_id, 'status': 'waiting_input'}
        self._launch(run_id, 'resume')
        return {'run_id': run_id, 'status': 'queued'}

    def run_steer(self, id, text, run_id=None, input_id=None):
        self._chat_row(id)
        if run_id is None:
            candidates = [r for r in self._run_rows(id) if r['state'] in LIVE_STATES | WAITING_STATES]
            if not candidates:
                raise PebbleError('This conversation has no run to steer.')
            run_id = candidates[0]['id']
        run = self.runs.get(run_id)
        if not run or run['chat_id'] != id:
            raise PebbleError('Run not found in this conversation.')
        return self._steer(run_id, text, input_id)

    def _steer(self, run_id, text, input_id=None):
        if not isinstance(text, str) or not text.strip() or len(text) > 8000:
            raise PebbleError('Enter guidance under 8,000 characters.')
        run = self.runs[run_id]
        if run['state'] not in LIVE_STATES | RESUMABLE:
            raise PebbleError('This run cannot accept follow-up input.')
        ident = input_id or _hex()
        run['steer'].append(ident)
        self._journal(run_id, 'input_queued', {'input_id': ident, 'kind': 'steering', 'origin': 'human'})
        return {'input_id': ident, 'run_id': run_id, 'status': 'queued'}

    def _find_action(self, cid, action_id):
        self._chat_row(cid)
        return next((a for a in self.actions[cid] if a['id'] == action_id), None)

    def _simple_card(self, id, action_id):
        action = self._find_action(id, action_id)
        if not action or action['status'] != 'pending':
            raise PebbleError('This action is no longer awaiting approval.')
        if action['kind'] not in SIMPLE_CARDS:
            raise PebbleError('Review this one in the workspace.')
        return True

    async def approve(self, id, action_id):
        if self.active:
            raise PebbleError('Wait for the current task to finish before approving an action.')
        action = self._find_action(id, action_id)
        if not action or action['status'] != 'pending':
            raise PebbleError('This action is no longer awaiting approval.')
        owner = self.action_runs.get(action_id)
        self.active, self.active_run = id, None
        action['status'] = 'running'
        self.emit('actions', {'chat_id': id, 'actions': [dict(a) for a in self.actions[id]]})
        try:
            await self.sleep(1.2)  # the command runs
            result = self._perform(action)
            action['status'] = 'applied'
            action['payload'] = {**action['payload'], 'result': result}
            summary = ('Ran `' + action['payload'].get('command', '') + '` with exit code ' + str(result['exit_code'])
                       + '.\n\n```text\n' + result['output'] + '\n```') if action['kind'] == 'command' \
                else 'Done: ' + action['kind'] + '.'
            self._add_message(id, 'assistant', summary)
        finally:
            self.active, self.active_run = None, None
            self.emit('actions', {'chat_id': id, 'actions': [dict(a) for a in self.actions[id]]})
            self.emit('idle', {'chat_id': id, 'run_id': owner})
        if owner and self.runs[owner]['state'] == 'waiting_approval':
            self.runs[owner]['continuation'] = 'approved'
            self._launch(owner, 'continue')
        return result

    @staticmethod
    def _perform(action):
        if action['kind'] == 'command':
            if action['payload'].get('command') == 'npm test':
                output = ('> shop-web@2.4.0 test\n> vitest run\n\n ✓ src/auth/redirect.test.ts (6 tests) 41ms\n'
                          ' ✓ src/cart/total.test.ts (14 tests) 63ms\n ✓ src/ui/button.test.ts (22 tests) 118ms\n\n'
                          ' Test Files  3 passed (3)\n      Tests  42 passed (42)\n   Duration  3.12s')
            else:  # a command the phone proposed (terminal_propose): the mock never runs one
                output = '(Simulated: nothing was run on this Mac.)'
            return {'exit_code': 0, 'output': output, 'output_projection': 'terminal_text/1', 'controls_removed': 0,
                    'raw_output_sha256': hashlib.sha256(output.encode()).hexdigest(),
                    'command': action['payload'].get('command'),
                    'isolation': 'macOS sandbox · selected project · network '
                                 + ('allowed' if action['payload'].get('network') else 'denied')}
        return {'status': 'done'}

    def reject(self, id, action_id):
        action = self._find_action(id, action_id)
        if not action or action['status'] != 'pending':
            raise PebbleError('This action is no longer awaiting approval.')
        action['status'] = 'rejected'
        self.emit('actions', {'chat_id': id, 'actions': [dict(a) for a in self.actions[id]]})
        owner = self.action_runs.get(action_id)
        if owner and self.runs[owner]['state'] == 'waiting_approval':
            self.runs[owner]['continuation'] = 'rejected'
            self._launch(owner, 'continue')
        return True

    def undo(self, id, action_id):
        if self.active:
            raise PebbleError('Wait for the current task to finish before undoing an edit.')
        action = self._find_action(id, action_id)
        if not action or action['kind'] != 'edit' or action['status'] != 'applied':
            raise PebbleError('Only applied file edits can be undone.')
        action['status'] = 'undone'
        self.emit('actions', {'chat_id': id, 'actions': [dict(a) for a in self.actions[id]]})
        return {'path': action['payload'].get('path'), 'undone': True}

    @staticmethod
    def _canonical(items, answers):
        if not isinstance(answers, dict) or set(answers) != {i['id'] for i in items}:
            raise PebbleError('Answer each requested question exactly once.')
        result = {}
        for item in items:
            answer = answers[item['id']]
            if not isinstance(answer, dict) or set(answer) not in ({'option_id'}, {'text'}):
                raise PebbleError('Choose an option or enter free text.')
            if 'option_id' in answer:
                option = next((o for o in item['options'] if o['id'] == answer['option_id']), None)
                if not option:
                    raise PebbleError('Choose an offered option or use free text.')
                result[item['id']] = {'option_id': option['id'], 'text': option['label']}
            else:
                text = answer['text']
                if not isinstance(text, str) or not text.strip() or len(text) > 2000:
                    raise PebbleError('Enter an answer under 2,000 characters.')
                result[item['id']] = {'text': text.strip()}
        return result

    def _question(self, cid, question_id):
        q = self.questions.get(question_id)
        if not q or q['chat_id'] != cid:
            raise PebbleError('Question not found in this conversation.')
        return q

    def question_answer(self, id, question_id, revision, answers):
        q = self._question(id, question_id)
        if type(revision) is not int or revision != q['revision']:
            raise PebbleError('This question revision is stale. Refresh it before answering.')
        canonical = self._canonical(q['items'], answers)
        said = [a['text'] for a in canonical.values()]
        message = {'id': 'answer-' + question_id, 'role': 'user',
                   'content': said[0] if len(said) == 1 else '\n'.join(said)}
        result = {'question_id': question_id, 'run_id': q['run_id'], 'status': 'answered', 'message': message}
        if q['status'] == 'answered' and canonical == q['answer']:
            return result
        if q['status'] != 'pending':
            raise PebbleError('This question is no longer accepting answers.')
        q.update(status='answered', answer=canonical, answered=_now())
        self._add_message(id, 'user', message['content'], mid=message['id'])
        self.emit('question', {'chat_id': id, **result, 'question': self._question_view(q)})
        run = self.runs[q['run_id']]
        if run['state'] == 'waiting_input':
            run['continuation'] = 'answered:' + message['content'][:200]
            self._launch(run['id'], 'continue')
        return result

    def question_cancel(self, id, question_id, revision):
        q = self._question(id, question_id)
        if type(revision) is not int or revision != q['revision']:
            raise PebbleError('This question revision is stale. Refresh it before answering.')
        if q['status'] != 'pending':
            raise PebbleError('This question is no longer accepting answers.')
        q['status'] = 'cancelled'
        result = {'question_id': question_id, 'run_id': q['run_id'], 'status': 'cancelled', 'required': q['required']}
        self.emit('question', {'chat_id': id, **result, 'question': self._question_view(q)})
        run = self.runs[q['run_id']]
        if run['state'] == 'waiting_input':
            run['continuation'] = 'cancelled'
            self._launch(run['id'], 'continue')
        return result

    def setting(self, key, value):
        """App.setting: every key Pebble accepts, with its checks and words (backend/pebble/app.py, settings_file.py,
        companion_settings.py). SETTING_CLASSES classifies these same keys."""
        if key == 'permissions':
            if self.active:
                raise PebbleError('Stop the task before changing permissions.')
            self.settings['permissions'] = self._permissions(value)
        elif key == 'fast_replies':
            if value not in FAST:
                raise PebbleError('Choose off, follow-ups, long tasks or always.')
            self.settings[key] = value
        elif key == 'git_decisions':
            if not isinstance(value, dict) or set(value) != set(GIT_DECISIONS) or \
                    any(type(v) is not bool for v in value.values()):
                raise PebbleError('git_decisions needs true or false for each of: ' + ', '.join(GIT_DECISIONS) + '.')
            self.settings[key] = dict(value)
        elif key == 'memory_layers':
            if not isinstance(value, dict) or set(value) != set(MEMORY_LAYERS) or \
                    any(type(v) is not bool for v in value.values()):
                raise PebbleError('Supply one boolean for each of the six memory layers.')
            self.settings[key] = dict(value)
        elif key in ('reduced_motion', 'memory_enabled', 'stealth') and isinstance(value, bool):
            self.settings[key] = value
        elif key == 'theme' and value in ('system', 'light', 'dark'):
            self.settings[key] = value
        elif key == 'companion':
            if not isinstance(value, dict) or set(value) != {'pointer', 'reactions', 'status_words', 'ui_guidance'} or \
                    any(type(value[k]) is not bool for k in ('pointer', 'reactions', 'ui_guidance')) or \
                    value['status_words'] not in ('rotate', 'fixed', 'off'):
                raise PebbleError('Choose each companion switch and how status words show.')
            self.settings[key] = dict(value)
        elif key == 'notifications':
            if not isinstance(value, dict) or type(value.get('enabled')) is not bool or \
                    value.get('preview') not in ('none', 'title', 'body') or not isinstance(value.get('kinds'), dict):
                raise PebbleError('Choose whether notifications show, what they show, and which kinds.')
            self.notification_settings = {**self.notification_settings, **value}
        else:
            raise PebbleError('Setting is not supported.')
        self.emit('settings', {})
        return True

    @staticmethod
    def _permissions(value):
        if not isinstance(value, dict) or value.get('mode') not in MODES or not isinstance(value.get('tools'), dict):
            raise PebbleError('Choose a permission mode and a setting for each tool.')
        tools = value['tools']
        if any(type(tools.get(name)) is not bool for name in TOOL_SWITCHES) or \
                set(tools) - set(TOOL_SWITCHES) - set(OPTIONAL_SWITCHES):
            raise PebbleError('Choose a permission mode and a setting for each tool.')
        return {'mode': value['mode'],
                'tools': {**{name: tools[name] for name in TOOL_SWITCHES},
                          **{name: tools.get(name, default) is True for name, default in OPTIONAL_SWITCHES.items()}}}

    def model_select(self, profile_id):
        if self.active:
            raise PebbleError('Stop the current task before changing models.')
        if not any(p['id'] == profile_id for p in self.profiles):
            raise PebbleError('That model is not connected.')
        self.selected = profile_id
        status = self.model_status()
        self.emit('model', status)
        return status

    def model_effort(self, effort):
        if self.active:
            raise PebbleError('Stop the current task before changing effort.')
        if effort not in ('low', 'medium', 'high'):
            raise PebbleError('Choose low, medium or high effort.')
        self.effort = effort
        status = self.model_status()
        self.emit('model', status)
        return status

    def screen_session_revoke(self, session_id):
        session = self.screens.get(session_id)
        if session is None:
            raise PebbleError('That window is no longer shared.')
        session['state'] = 'revoked'
        return {'session_id': session_id, 'state': 'revoked'}

    # -- runs ---------------------------------------------------------------------------------------------------------

    def _transition(self, rid, state):
        run = self.runs[rid]
        run['state'], run['updated'] = state, _now()
        self._journal(rid, 'state', {'to': state})

    def _journal(self, rid, kind, payload):
        events = self.run_events.setdefault(rid, [])
        events.append({'run_id': rid, 'sequence': len(events) + 1, 'kind': kind, 'payload': payload,
                       'created': _now()})

    def _launch(self, rid, phase):
        run = self.runs[rid]
        self._transition(rid, 'queued')
        self.emit('run', {'chat_id': run['chat_id'], 'run_id': rid, 'state': 'queued'})
        if self.active and self.active_run != rid:
            self.pending_launches.append((rid, phase))  # one task at a time: it starts when the lane is free
            return
        self.active, self.active_run = run['chat_id'], rid
        self.tasks[rid] = asyncio.get_running_loop().create_task(self._drive(rid, phase))

    def _next_launch(self):
        while self.pending_launches and not self.active:
            rid, phase = self.pending_launches.popleft()
            if self.runs[rid]['state'] == 'queued':
                run = self.runs[rid]
                self.active, self.active_run = run['chat_id'], rid
                self.tasks[rid] = asyncio.get_running_loop().create_task(self._drive(rid, phase))

    def _progress(self, cid, rid, label, kind='working', tool=None, **extra):
        data = {'chat_id': cid, 'run_id': rid, 'label': label, 'kind': kind, **({'tool': tool} if tool else {}),
                **extra, 'activity': classify(tool, kind)}
        self.emit('progress', data)
        items = self.activity.setdefault(rid, [])
        if kind == 'done' and items and items[-1]['label'] == label and items[-1]['status'] == 'running':
            item = items[-1]
            item['status'] = 'done'
            item['duration'] = round(max(0.0, self._run_clock(rid) - item['at']), 3)
            self.emit('activity', {'chat_id': cid, 'run_id': rid, 'item': dict(item)})
        elif kind in ('working', 'review', 'blocked'):
            self._activity_item(cid, rid, 'tool' if tool else 'note', label,
                                status='running' if kind == 'working' and tool else 'done')

    def _run_clock(self, rid):
        return round(max(0.0, _now() - self.runs[rid]['created']), 3)

    def _activity_item(self, cid, rid, kind, label, detail=None, duration=None, status='done'):
        """One timeline item as run_activity.items() shapes it, emitted as Pebble's ActivityFeed does (C4)."""
        items = self.activity.setdefault(rid, [])
        item = {'seq': (len(items) + 1) * 10, 'at': self._run_clock(rid), 'kind': kind, 'label': label,
                'detail': detail, 'duration': duration, 'status': status,
                **({'headers_ms': None, 'first_event_ms': None} if kind == 'model' else {})}
        items.append(item)
        self.emit('activity', {'chat_id': cid, 'run_id': rid, 'item': dict(item)})

    async def _reason(self, cid, rid, text):
        attempt = 'att-' + _hex()[:12]
        for part in re.findall(r'.{1,18}(?:\s+|$)', text):
            self.emit('reasoning', {'chat_id': cid, 'run_id': rid, 'attempt_id': attempt, 'delta': part})
            self.reasoning[rid] = self.reasoning.get(rid, '') + part
            await self.sleep(0.03)

    async def _say(self, cid, rid, mid, text, state, interval=0.02):
        """Stream text as token events in small uneven pieces (some arrive within 30 ms of each other)."""
        rng = random.Random(rid + mid)
        position = 0
        while position < len(text):
            size = rng.randint(1, 6)
            part = text[position:position + size]
            position += size
            state['answer'] += part
            self.emit('token', {'chat_id': cid, 'id': mid, 'text': part})
            run = self.runs[rid]
            if run['steer'] and state['steered'] < len(run['steer']):
                state['steered'] = len(run['steer'])
                note = '\n\n(Noted your guidance; adjusting.)\n\n'
                state['answer'] += note
                self.emit('token', {'chat_id': cid, 'id': mid, 'text': note})
            await self.sleep(interval * rng.uniform(0.4, 1.6))

    def _finish(self, cid, rid, mid, answer, started):
        seconds = time.monotonic() - started
        # The reply's model attempt commits (runner.py `stream` events), and the timeline gets its model item.
        self.emit('stream', {'chat_id': cid, 'run_id': rid, 'attempt_id': 'att-' + mid[:12], 'type': 'commit',
                             'authorization': 'none'})
        self._activity_item(cid, rid, 'model', 'Wrote the reply', duration=round(seconds * self.speed, 3))
        self._add_message(cid, 'assistant', answer, mid=mid, run_id=rid)
        usage = self._usage(answer, seconds)
        self.metrics[mid] = usage
        self.emit('usage', {'chat_id': cid, 'id': mid, 'usage': usage})
        self.emit('complete', {'chat_id': cid, 'id': mid, 'seconds': usage['seconds']})

    def _settle(self, rid, state, started):
        run = self.runs[rid]
        run['elapsed'] = round(run['elapsed'] + (time.monotonic() - started) * self.speed, 3)
        self._transition(rid, state)
        self.emit('run', {'chat_id': run['chat_id'], 'run_id': rid, 'state': state, 'elapsed': run['elapsed']})

    @staticmethod
    def scenario(text):
        lower = text.lower()
        if 'test' in lower:
            return 'card'
        if 'ask me' in lower or 'question' in lower or 'which' in lower:
            return 'question'
        if 'slow' in lower or 'long' in lower:
            return 'long'
        return 'reply'

    async def _drive(self, rid, phase):
        run = self.runs[rid]
        cid = run['chat_id']
        workspace = self.chats[cid]['workspace']
        mid = _hex()
        state = {'answer': '', 'steered': len(run['steer'])}
        started = time.monotonic()
        outcome = 'completed'
        try:
            await self.sleep(0.15)
            self._transition(rid, 'running')
            self.emit('run', {'chat_id': cid, 'run_id': rid, 'state': 'running'})
            self._activity_item(cid, rid, 'context', 'Context ready', 'Context ready in 120 ms', 0.12)
            await self.sleep(0.1)
            kind = self.scenario(run['goal']) if phase == 'start' else phase
            if phase == 'start' and workspace:
                self._progress(cid, rid, 'Preparing your local workspace')
                await self.sleep(0.2)
            if kind == 'card':
                await self._reason(cid, rid, 'The person wants the tests run. I should find how this project runs '
                                             'its tests, then ask before running them.')
                label = tool_label('ListProjectRecipes', {})
                self._progress(cid, rid, label, tool='ListProjectRecipes')
                await self.sleep(0.4)
                self._progress(cid, rid, label, 'done', tool='ListProjectRecipes')
                await self._say(cid, rid, mid, "I'll run the project's tests first to see what fails.", state)
                label = tool_label('RunCommand', {})
                self._progress(cid, rid, label, tool='RunCommand')
                await self.sleep(0.2)
                aid = self._add_action(cid, 'command', 'pending', self._command_payload('npm test'), run_id=rid)
                self.action_runs[aid] = rid
                self.emit('actions', {'chat_id': cid, 'actions': [dict(a) for a in self.actions[cid]]})
                self._progress(cid, rid, WITHHELD_APPROVAL, 'review')
                self._finish(cid, rid, mid, state['answer'], started)
                outcome = 'waiting_approval'
                return
            if kind == 'question':
                await self._reason(cid, rid, 'There are two groups of beds. I should ask which to plan first.')
                label = tool_label('AskUserQuestion', {})
                self._progress(cid, rid, label, tool='AskUserQuestion')
                await self.sleep(0.3)
                self._progress(cid, rid, label, 'done', tool='AskUserQuestion')
                qid = self._new_question(rid, cid)
                self.emit('question', {'chat_id': cid, 'run_id': rid, 'question_id': qid, 'status': 'pending',
                                       'question': self._question_view(self.questions[qid])})
                self._progress(cid, rid, WAITING_ANSWER, 'review')
                outcome = 'waiting_input'
                return
            if kind == 'continue':
                decided = run.get('continuation') or ''
                text = self._continuation_text(run)  # clears the decision
                await self._reason(cid, rid, 'Picking up after the decision.')
                if decided.startswith('answered:'):
                    label = tool_label('UpdatePlan', {})
                    self._progress(cid, rid, label, tool='UpdatePlan')
                    plan = self.plans.get(rid) or {'run_id': rid, 'revision': 0, 'steps': []}
                    steps = [dict(s, status='completed' if s['id'] == 'beds' else
                                  'in_progress' if s['id'] == 'crops' else s['status']) for s in plan['steps']]
                    self.plans[rid] = {'run_id': rid, 'revision': plan['revision'] + 1, 'steps': steps,
                                       'updated': _now()}
                    self.emit('plan', {'chat_id': cid, **self.plans[rid]})
                    self._progress(cid, rid, label, 'done', tool='UpdatePlan')
                await self._say(cid, rid, mid, text, state)
            elif kind == 'resume':
                await self._say(cid, rid, mid, 'Picking up where I left off. ' + REPLIES[2], state)
            else:
                await self._reason(cid, rid, 'Reading the request and checking what is needed before answering.')
                if workspace:
                    for tool, args in (('Read', {'file_path': 'src/auth/redirect.ts'}), ('Grep', {})):
                        label = tool_label(tool, args)
                        self._progress(cid, rid, label, tool=tool)
                        await self.sleep(0.35)
                        self._progress(cid, rid, label, 'done', tool=tool)
                if kind == 'long':
                    # A helper agent and a background command, as Pebble's agent_manager and process_jobs report them
                    label = 'Starting a helper agent'
                    self._progress(cid, rid, label, tool='SpawnAgent')
                    agent = 'agent-' + _hex()[:8]
                    self.emit('agent', {'chat_id': cid, 'run_id': rid, 'agent_id': agent})
                    self._progress(cid, rid, label, 'done', tool='SpawnAgent')
                    process = 'proc-' + _hex()[:8]
                    self._progress(cid, rid, 'Starting a background command', tool='StartCommand')
                    self.emit('process', {'chat_id': cid, 'run_id': rid, 'process_id': process, 'state': 'running'})
                    await self._say(cid, rid, mid, LONG_REPLY, state, interval=0.06)
                    self.emit('process', {'chat_id': cid, 'run_id': rid, 'process_id': process, 'state': 'exited'})
                    self._progress(cid, rid, 'Starting a background command', 'done', tool='StartCommand')
                else:
                    reply = 'ok' if 'single word ok' in run['goal'].lower() else \
                        REPLIES[int(hashlib.sha256(run['goal'].encode()).hexdigest(), 16) % len(REPLIES)]
                    await self._say(cid, rid, mid, reply, state)
            self._finish(cid, rid, mid, state['answer'], started)
        except asyncio.CancelledError:
            outcome = 'paused' if run['pause'] else 'stopped'
            run['pause'] = False
            if state['answer']:
                self._add_message(cid, 'assistant', state['answer'], mid=mid, run_id=rid)
            self.emit('stopped', {'chat_id': cid, 'id': mid})
        finally:
            run['steps'] += 3
            self._settle(rid, outcome, started)
            if self.active_run == rid:
                self.active, self.active_run = None, None
            self.emit('idle', {'chat_id': cid, 'run_id': rid})
            self.tasks.pop(rid, None)
            self._next_launch()

    @staticmethod
    def _continuation_text(run):
        decided = run.get('continuation') or ''
        run['continuation'] = None
        if decided == 'approved':
            return ('All 42 tests passed in 3.1 s, so nothing is failing right now.\n\nThe slowest file is '
                    '`src/ui/button.test.ts` (118 ms). If you saw a failure earlier, it may depend on the order the '
                    'files run in; I can run them one at a time to check.')
        if decided == 'rejected':
            return "Okay, I didn't run the tests. Tell me if you'd like me to look at the test files without running them."
        if decided == 'cancelled':
            return "Okay, I'll stop here. Tell me when you'd like to pick this up again."
        answer = decided.split(':', 1)[1] if ':' in decided else ''
        return ('Got it: **' + answer + '** first.\n\n| Bed | Crop | Sow |\n|---|---|---|\n| 1 | Lettuce | March |\n'
                '| 2 | Peas | March |\n| 3 | Beans | May |\n\nNext I can match the remaining beds to sun and soil.')


# =====================================================================================================================
# The bridge's identity and the paired phones
# =====================================================================================================================

def test_pattern_png(width, height, mirrored=False):
    """A screen-sized test pattern as PNG bytes (8-bit RGB), written with zlib alone: colour bars, a grey ramp and a
    checkerboard inside a frame in Pebble's sage. `mirrored` reverses the bars, so two displays look different.
    Distinct rows are built once and repeated, so even 2560x1440 takes a fraction of a second."""
    import zlib
    sage = bytes((80, 110, 84))
    edge = max(4, width // 160)
    inner = width - 2 * edge
    bars = [(235, 235, 235), (235, 235, 16), (16, 235, 235), (16, 235, 16), (235, 16, 235), (235, 16, 16),
            (16, 16, 235), (16, 16, 16)]
    if mirrored:
        bars.reverse()
    bar_row = b''.join(bytes(colour) * (inner * (i + 1) // 8 - inner * i // 8) for i, colour in enumerate(bars))
    ramp_row = bytes(v for x in range(inner) for v in (255 * x // max(1, inner - 1),) * 3)
    cell = 32
    checker = [b''.join((b'\xd8\xd8\xd8' if (x // cell + parity) % 2 else b'\x30\x30\x30') for x in range(inner))
               for parity in (0, 1)]

    def framed(row):
        return b'\x00' + sage * edge + row + sage * edge  # filter byte 0, then the pixels

    solid = b'\x00' + sage * width
    inner_height = height - 2 * edge
    bars_end, ramp_end = inner_height * 60 // 100, inner_height * 75 // 100
    rows = [solid] * edge
    for y in range(inner_height):
        if y < bars_end:
            rows.append(framed(bar_row))
        elif y < ramp_end:
            rows.append(framed(ramp_row))
        else:
            rows.append(framed(checker[((y - ramp_end) // cell) % 2]))
    rows += [solid] * edge

    def chunk(kind, data):
        return len(data).to_bytes(4, 'big') + kind + data + zlib.crc32(kind + data).to_bytes(4, 'big')

    header = width.to_bytes(4, 'big') + height.to_bytes(4, 'big') + bytes((8, 2, 0, 0, 0))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(b''.join(rows), 6))
            + chunk(b'IEND', b''))


def make_test_screens(displays, folder=None):
    """{index: JPEG bytes} for each (index, width, height), converted from test_pattern_png by /usr/bin/sips."""
    import tempfile
    screens = {}
    with tempfile.TemporaryDirectory(dir=folder) as work:
        for index, width, height in displays:
            png, jpeg = os.path.join(work, 'screen-%d.png' % index), os.path.join(work, 'screen-%d.jpg' % index)
            with open(png, 'wb') as handle:
                handle.write(test_pattern_png(width, height, mirrored=index % 2 == 1))
            done = subprocess.run(['/usr/bin/sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '70', png,
                                   '--out', jpeg], capture_output=True, timeout=60, stdin=subprocess.DEVNULL)
            if done.returncode != 0 or not os.path.exists(jpeg):
                raise RuntimeError('sips could not make a JPEG')
            with open(jpeg, 'rb') as handle:
                screens[index] = handle.read()
    return screens


def find_openssl():
    for candidate in (os.environ.get('PEBBLE_MOCK_OPENSSL'), '/usr/bin/openssl'):
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    raise SystemExit('mock: the openssl command-line tool is missing (expected /usr/bin/openssl)')


def _write_private(path, data):
    temporary = path + '.tmp'
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'wb') as handle:
        handle.write(data)
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


class Identity:
    """The bridge's TLS key and certificate (made with openssl), its pin and its bridge id, in the state folder.

    The key is kept; the certificate is re-issued with the same key when it is missing, about to expire, or does not
    match the key, so the pin stays the same and a paired phone needs no new pairing (section 3.1)."""

    def __init__(self, state_dir, openssl=None):
        self.dir = state_dir
        os.makedirs(state_dir, mode=0o700, exist_ok=True)
        os.chmod(state_dir, 0o700)
        self.openssl = openssl or find_openssl()
        self.key_path = os.path.join(state_dir, 'tls-key.pem')
        self.cert_path = os.path.join(state_dir, 'tls-cert.pem')
        previous = os.umask(0o077)
        try:
            if not os.path.exists(self.key_path):
                self._run('ecparam', '-name', 'prime256v1', '-param_enc', 'named_curve', '-genkey', '-noout',
                          '-out', self.key_path)
                log('made a new P-256 TLS key')
            key_spki = self._run('ec', '-in', self.key_path, '-pubout', '-outform', 'DER', capture=True)
            if not self._certificate_ok(key_spki):
                self._run('req', '-new', '-x509', '-key', self.key_path, '-out', self.cert_path, '-days', '397',
                          '-subj', '/CN=Pebble Remote bridge', '-sha256')
                log('issued a self-signed certificate for the key')
        finally:
            os.umask(previous)
        for path in (self.key_path, self.cert_path):
            os.chmod(path, 0o600)
        with open(self.cert_path) as handle:
            self.cert_der = ssl.PEM_cert_to_DER_cert(handle.read())
        self.spki = wire.spki_from_certificate(self.cert_der)
        self.pin = wire.spki_pin(self.spki)
        meta_path = os.path.join(state_dir, 'bridge.json')
        meta = {}
        if os.path.exists(meta_path):
            with open(meta_path) as handle:
                meta = json.load(handle)
        if not isinstance(meta.get('bid'), str):
            meta = {'bid': 'b-' + wire.b64u(os.urandom(12)), 'created': wire.now_ms()}
            _write_private(meta_path, json.dumps(meta).encode())
        self.bid = meta['bid']

    def _run(self, *args, capture=False):
        done = subprocess.run([self.openssl, *args], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
        if done.returncode != 0:
            raise SystemExit('mock: openssl ' + args[0] + ' failed: ' + done.stderr.decode(errors='replace')[:300])
        return done.stdout if capture else None

    def _certificate_ok(self, key_spki):
        if not os.path.exists(self.cert_path):
            return False
        try:
            with open(self.cert_path) as handle:
                der = ssl.PEM_cert_to_DER_cert(handle.read())
            if wire.spki_from_certificate(der) != key_spki:
                return False
        except (ValueError, OSError):
            return False
        check = subprocess.run([self.openssl, 'x509', '-checkend', str(7 * 86400), '-noout', '-in', self.cert_path],
                               stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
        return check.returncode == 0

    def tls_context(self):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.load_cert_chain(self.cert_path, self.key_path)
        return context


class Registry:
    """Paired phones (devices.json, mode 600): id, name, both public keys, paired and last-seen times; revoked ids."""

    def __init__(self, path):
        self.path = path
        self.devices, self.revoked = {}, {}
        if os.path.exists(path):
            with open(path) as handle:
                data = json.load(handle)
            self.devices = data.get('devices', {})
            self.revoked = data.get('revoked', {})

    def save(self):
        _write_private(self.path, json.dumps({'devices': self.devices, 'revoked': self.revoked}, indent=1).encode())

    def add(self, device, device_key, approve_key):
        device_id = 'd-' + wire.b64u(os.urandom(12))
        now = wire.now_ms()
        self.devices[device_id] = {
            'device_id': device_id, 'name': str(device.get('name') or 'iPhone')[:80],
            'model': str(device.get('model') or '')[:40], 'os': str(device.get('os') or '')[:40],
            'app': str(device.get('app') or '')[:40], 'device_key': device_key, 'approve_key': approve_key,
            'paired_at': now, 'last_seen': now}
        self.save()
        return self.devices[device_id]

    def get(self, device_id):
        return self.devices.get(device_id) if isinstance(device_id, str) else None

    def revoke(self, device_id):
        if device_id not in self.devices:
            return False
        del self.devices[device_id]
        self.revoked[device_id] = wire.now_ms()
        self.save()
        return True

    def touch(self, device_id, app=None):
        record = self.devices.get(device_id)
        if record is not None:
            record['last_seen'] = wire.now_ms()
            if isinstance(app, str):
                record['app'] = app[:40]
            self.save()

    def listing(self, current=None):
        rows = [{'device_id': d['device_id'], 'name': d['name'], 'paired_at': d['paired_at'],
                 'last_seen': d['last_seen']} for d in self.devices.values()]
        if current is not None:
            for row in rows:
                row['current'] = row['device_id'] == current
        return rows


class TokenBucket:
    def __init__(self, burst=RATE_BURST, rate=RATE_PER_SECOND):
        self.burst, self.rate = burst, rate
        self.tokens, self.at = float(burst), time.monotonic()

    def take(self):
        now = time.monotonic()
        self.tokens = min(self.burst, self.tokens + (now - self.at) * self.rate)
        self.at = now
        if self.tokens >= 1:
            self.tokens -= 1
            return True
        return False


class FolderRefused(Exception):
    """A refusal of `remote.folders`: words for the person, and the bridge's code when there is one (`not_allowed`,
    `bad_request`). A folder that is not there is a refusal in words only, as Pebble gives it."""

    def __init__(self, words, code=None):
        super().__init__(words)
        self.words, self.code = words, code


class Folders:
    """Proposal v0.5, `remote.folders`: the home folder as the phone may browse it, or the test tree of --folders-root.

    - **What it lists:** subfolders only, never files, never file names or contents. Links are left out.
    - **Left out:** hidden folders (a leading dot, or macOS's hidden flag, which `~/Library` has), Pebble's protected
      list (the Shell sandbox's, `remote_wire.PROTECTED_*`), and the folders in `extra_protected` (the mock's own state
      folder, with its keys).
    - **Only inside home:** a `path` must be the real path of a folder in home, spelled as the listing spells it: a
      link or a `..` in it, or a place outside home, gets `not_allowed`, and so does a folder with a hidden or protected
      folder above it. A `path` that is not an absolute string is `bad_request`.
    - **The listing:** sorted by name, at most 500 entries, `is_project` when `.git` exists (a folder, or the file a
      worktree has).

    `listable(path)` says whether `remote.folders` would list a folder: the rule `set_workspace` and `new_chat` use for
    a folder the Mac does not use yet."""

    def __init__(self, root=None, extra_protected=()):
        self.home = os.path.realpath(root or os.path.expanduser('~'))
        self.extra = [os.path.realpath(path) for path in extra_protected if path]
        self.bases = None

    def left_out(self, path, name, info=None):
        """Why a folder is not shown ('hidden' or 'protected'), or None. `path` is a real path; `info` is its lstat,
        for macOS's hidden flag."""
        if name.startswith('.') or (info is not None and getattr(info, 'st_flags', 0) & getattr(stat, 'UF_HIDDEN', 0)):
            return 'hidden'
        if wire.protected_entry(self.home, path, self.extra, bases=self.bases, resolved=True):
            return 'protected'
        return None

    def inside_home(self, real):
        return real == self.home or real.startswith(self.home.rstrip('/') + '/')

    def locate(self, path):
        """The real path of the folder `path` names (None is home), or FolderRefused."""
        # Resolving Pebble's whole protected list costs a few milliseconds: once for each request, not for each folder
        self.bases = wire.protected_bases(self.home, self.extra)
        if path is None:
            return self.home
        if not isinstance(path, str) or not path or len(path) > 4096 or '\x00' in path or not path.startswith('/'):
            raise FolderRefused(ERRORS['bad_request'], 'bad_request')
        given = path.rstrip('/') or '/'
        real = os.path.realpath(given)
        if real != given or not self.inside_home(real):  # a link, a `..`, a doubled slash, or somewhere else
            raise FolderRefused(FOLDER_WORDS['outside'], 'not_allowed')
        here = self.home
        for part in [p for p in real[len(self.home):].split('/') if p]:  # each folder on the way must be a shown one
            here = os.path.join(here, part)
            try:
                info = os.lstat(here)
            except OSError:
                info = None  # not there: a hidden or protected name is refused all the same, so nothing is given away
            if self.left_out(here, part, info):
                raise FolderRefused(FOLDER_WORDS['private'], 'not_allowed')
        if not os.path.isdir(real):
            raise FolderRefused(FOLDER_WORDS['missing'])
        return real

    def _row(self, parent, entry):
        try:
            if entry.is_symlink() or not entry.is_dir(follow_symlinks=False):
                return None
            info = entry.stat(follow_symlinks=False)
            entry.name.encode('utf-8')  # a name that is not valid UTF-8 cannot be sent
        except (OSError, UnicodeEncodeError):
            return None
        path = os.path.join(parent, entry.name)
        if self.left_out(path, entry.name, info):
            return None
        return {'name': entry.name, 'path': path, 'is_project': os.path.lexists(os.path.join(path, '.git'))}

    def listing(self, path=None):
        """`{home, path, parent, folders: [{name, path, is_project}]}`; `parent` is null at home."""
        real = self.locate(path)
        rows = []
        try:
            with os.scandir(real) as entries:
                for entry in entries:
                    row = self._row(real, entry)
                    if row is not None:
                        rows.append(row)
        except PermissionError:
            raise FolderRefused(FOLDER_WORDS['unreadable']) from None
        except OSError:
            raise FolderRefused(FOLDER_WORDS['missing']) from None
        rows.sort(key=lambda row: (row['name'].casefold(), row['name']))
        return {'home': self.home, 'path': real, 'parent': None if real == self.home else os.path.dirname(real),
                'folders': rows[:wire.FOLDERS_LIMIT]}

    def listable(self, path):
        """Whether `remote.folders` would list this folder: a real folder below home, through folders it shows."""
        if not isinstance(path, str):
            return False
        try:
            return self.locate(path) != self.home
        except FolderRefused:
            return False

    def create(self, parent, name):
        """Proposal v0.6, `remote.folder_create {parent, name}`: makes one empty folder, for real, in this Mac's home
        folder or in the test tree of --folders-root. `{path, name, is_project: false}` is the entry as the listing
        gives it, so `path` can be sent back as it is.

        - **parent:** an absolute path `remote.folders` would list, the home folder included; null is not a parent.
          The same rules as a listing: a place outside home, a `..`, a link, a hidden or protected folder gets
          `not_allowed`; a folder that is not there gets words and no code.
        - **name:** trimmed, then 1 to 255 bytes of UTF-8 with no `/` or `:`, no control characters, not `.` or `..`, no
          leading dot; a name outside the rules gets `bad_request`, with words that say which rule. The mock adds one: a
          name the listing would leave out (`secrets`, `*.key`, ...) is refused too (`bad_request`), because the folder
          could never be shown or connected.
        - **One empty folder:** never an intermediate folder, and nothing inside it. A name already in the parent
          (a folder, or a file) gets "A folder with that name is already there." and no code; a write that fails gets
          words and no code. The disk decides what is already there, so two phones cannot both make it."""
        if not isinstance(parent, str) or not isinstance(name, str):
            raise FolderRefused(ERRORS['bad_request'], 'bad_request')
        name = wire.trim_folder_name(name)
        problem = wire.folder_name_problem(name)
        if problem:
            raise FolderRefused(NAME_WORDS[problem], 'bad_request')
        real = self.locate(parent)
        path = os.path.join(real, name)
        if wire.protected_entry(self.home, path, self.extra, exists=lambda _: True, bases=self.bases, resolved=True):
            raise FolderRefused(NAME_WORDS['private'], 'bad_request')
        try:
            # Made inside the folder that was just checked, not wherever its name leads a moment later
            handle = os.open(real, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        except OSError:
            raise FolderRefused(FOLDER_WORDS['not_made']) from None
        try:
            os.mkdir(name, dir_fd=handle)
        except FileExistsError:
            raise FolderRefused(FOLDER_WORDS['exists']) from None
        except PermissionError:
            raise FolderRefused(FOLDER_WORDS['not_writable']) from None
        except OSError:
            raise FolderRefused(FOLDER_WORDS['not_made']) from None
        finally:
            os.close(handle)
        return {'path': path, 'name': name, 'is_project': False}


class PairConfirm:
    """X-1 (claude-w's 10:49 answer, item 3): after `pair` verifies, the Mac shows the six digits the phone shows, and the
    person confirms that they match. Here the "person" is one of three modes: `auto` confirms after a short delay (so
    the phone has time to show its code), `ask` prints the code and reads `y` or `n` from stdin, `refuse` cancels every
    pairing (for tests). No answer within `timeout` seconds (two minutes) is a refusal, as a cancel is."""

    def __init__(self, mode='auto', timeout=PAIR_CONFIRM_SECONDS, delay=PAIR_CONFIRM_AUTO_SECONDS):
        self.mode, self.timeout, self.delay = mode, float(timeout), float(delay)
        self.lines = None  # the lines read from stdin, for `ask`

    async def ask(self, code):
        """True when the person confirmed, False when they cancelled or did not answer in time."""
        try:
            return await asyncio.wait_for(self.decide(code), self.timeout)
        except (asyncio.TimeoutError, TimeoutError):
            log('pairing was not confirmed on the Mac within %g s' % self.timeout)
            return False

    async def decide(self, code):
        if self.mode == 'refuse':
            return False
        if self.mode == 'auto':
            await asyncio.sleep(self.delay)
            return True
        print('Pairing code %s. Does the iPhone show the same code? Confirm the pairing [y/n]:' % code,
              file=sys.stderr, flush=True)
        while True:
            answer = (await self.read_line()).strip().lower()
            if answer in ('y', 'yes'):
                return True
            if answer in ('n', 'no'):
                return False
            print('Type y or n:', file=sys.stderr, flush=True)

    async def read_line(self):
        """The next line from stdin. A thread of its own reads it (a daemon, so a question nobody answers never holds
        the process up when it stops); at the end of the input no line comes, and the question times out."""
        if self.lines is None:
            loop = asyncio.get_running_loop()
            self.lines = asyncio.Queue()

            def read():
                while True:
                    line = sys.stdin.readline()
                    if not line:
                        return
                    try:
                        loop.call_soon_threadsafe(self.lines.put_nowait, line)
                    except RuntimeError:  # the mock stopped while a question waited
                        return

            threading.Thread(target=read, daemon=True).start()
        return await self.lines.get()


# =====================================================================================================================
# The bridge
# =====================================================================================================================

class Conn:
    """One WebSocket connection. Everything sent goes through one queue and one writer task, so the order in which the
    bridge enqueues frames (welcome, replayed events, live events) is the order on the wire."""

    def __init__(self, bridge, ws, number):
        self.bridge, self.ws, self.number = bridge, ws, number
        self.nonce = wire.b64u(os.urandom(32))
        self.device = None
        self.live = False
        self.used_ids = set()
        self.queue = deque()
        self.queued = 0
        self.wake = asyncio.Event()
        self.closing = None   # (code, reason) once a close is wanted
        self.opened = time.monotonic()
        self.writer = None
        self.confirming = False  # X-1: a verified `pair` waits here for the person to confirm the code on the Mac
        self.pairing = None      # ... as this task

    def send(self, frame):
        if self.closing is not None:
            return
        text = frame if isinstance(frame, str) else dumps(frame)
        self.queue.append(text)
        self.queued += len(text)
        if self.queued > MAX_QUEUE:
            # The phone is not reading: a close frame would wait behind the same full socket, so drop the connection
            # at once. The phone reconnects and resumes from its last seq (section 3.5).
            log('conn#%d backpressure: more than 4 MB queued, dropping the connection' % self.number)
            self.queue.clear()
            self.queued = 0
            self.closing = (wire.CLOSE_TRY_LATER, 'too far behind')
            self.live = False
            self.ws.abort()
            self.wake.set()
            return
        self.wake.set()

    def bye(self, code, error=None):
        self.live = False
        self.send({'t': 'bye', 'code': code, 'error': error or BYE.get(code, '')})
        self.close(wire.CLOSE_NORMAL if code in ('replaced', 'revoked') else
                   wire.CLOSE_TOO_BIG if code == 'too_large' else wire.CLOSE_POLICY, code)

    def close(self, code=wire.CLOSE_NORMAL, reason=''):
        self.live = False
        if self.closing is None:
            self.closing = (code, reason)
            self.wake.set()

    async def writer_loop(self):
        try:
            while True:
                while self.queue:
                    text = self.queue.popleft()
                    self.queued -= len(text)
                    await self.ws.send_text(text)
                if self.closing is not None:
                    await self.ws.close(*self.closing)
                    return
                self.wake.clear()
                await self.wake.wait()
        except (ConnectionError, OSError, RuntimeError):
            self.ws.abort()


class Bridge:
    def __init__(self, identity, registry, *, name, speed=1.0, on_power=True, idle_timeout=45.0,
                 unlock_seconds=UNLOCK_SECONDS, proof_version=3, screen_recording=True, limit_loopback=False,
                 state_dir=None, folders_root=None, pair_confirm='auto', pair_confirm_timeout=PAIR_CONFIRM_SECONDS,
                 pair_confirm_delay=PAIR_CONFIRM_AUTO_SECONDS):
        self.identity, self.registry, self.name = identity, registry, name
        self.bid, self.pin = identity.bid, identity.pin
        self.epoch = 'e-' + wire.b64u(os.urandom(9))
        self.seq = 0
        self.buffer = deque()            # (seq, monotonic time, frame text or a function of the device id)
        self.conns, self.by_device = set(), {}
        self.counter = 0
        self.pairing = None
        self.idem = {}                   # (device id, idem) -> {'method', 'future', 'at'}
        self.buckets = {}
        self.batch = None                # a held token/reasoning event: {'key','name','data','at','timer'}
        self.idle_timeout = idle_timeout
        self.endpoints = []
        # R3: kept awake by default whenever Remote is on, on battery too
        self.mac = {'battery_percent': 92 if on_power else 64, 'charging': bool(on_power), 'on_power': bool(on_power),
                    'keep_awake': True}
        self.mac_emitted = 0.0
        self.on_link = None              # callback(link) when a pairing link opens
        self.on_pairing_code = None      # callback(code) when a pairing waits for the person to confirm its code (X-1)
        self.confirmer = PairConfirm(pair_confirm, pair_confirm_timeout, pair_confirm_delay)
        self.requests = set()            # running request tasks (asyncio keeps only weak references)
        self.unlock_seconds = int(unlock_seconds)
        self.unlocked = {}               # C1: device id -> (monotonic deadline, unix ms deadline)
        self.proofs = {}                 # C2: (device id, signature r) -> monotonic time accepted
        self.handshakes = {}             # C6: source address -> deque of monotonic times
        self.proof_version = proof_version
        self.screen_recording = screen_recording
        self.limit_loopback = limit_loopback
        self.state_dir = state_dir
        self.screens = None              # C3: the test pattern, made on first use
        # v0.5: remote.folders lists the real home folder, or the test tree of --folders-root. The mock's own state
        # folder (its TLS key and its paired phones) is never shown, as Pebble's own data folders are not.
        self.folders = Folders(folders_root, extra_protected=[state_dir] if state_dir else [])
        # v0.6: the folders each device made with remote.folder_create, as {device id: {real path: monotonic time}}. For
        # MADE_FOLDER_SECONDS such a folder counts as known to that device alone (made_by).
        self.made = {}
        self.sim = SimPebble(self.pebble_event, speed)

    # -- pairing ------------------------------------------------------------------------------------------------------

    def open_pairing(self):
        self.pairing = {'code': wire.b64u(os.urandom(16)), 'expires': time.monotonic() + PAIRING_SECONDS, 'tries': 0,
                        'used': False}
        link = wire.build_pairing_link(self.bid, self.name, self.pin, self.pairing['code'], self.endpoints)
        log('pairing open for 5 minutes, one phone, at most %d tries' % PAIRING_TRIES)
        if self.on_link:
            self.on_link(link)
        return link

    # -- events -------------------------------------------------------------------------------------------------------

    def pebble_event(self, name, data):
        """An event as Pebble emitted it. token/reasoning for the same reply or attempt that arrive within 30 ms of
        the first one held are merged (section 3.5); anything else first sends the held one, so nothing is reordered.
        Every event is forwarded unchanged (C4) except those the windows never get either."""
        if name in NEVER_FORWARDED:
            return
        key = None
        if name == 'token':
            key = ('token', data.get('chat_id'), data.get('id'))
        elif name == 'reasoning':
            key = ('reasoning', data.get('attempt_id'))
        now = time.monotonic()
        held = self.batch
        if held is not None:
            if key is not None and key == held['key'] and now - held['at'] <= BATCH_SECONDS:
                field = 'text' if name == 'token' else 'delta'
                held['data'][field] = held['data'].get(field, '') + data.get(field, '')
                return
            self.flush_batch()
        if key is not None:
            timer = asyncio.get_running_loop().call_later(BATCH_SECONDS, self.flush_batch)
            self.batch = {'key': key, 'name': name, 'data': dict(data), 'at': now, 'timer': timer}
            return
        self.publish(name, data)

    def flush_batch(self):
        held, self.batch = self.batch, None
        if held is not None:
            held['timer'].cancel()
            self.publish(held['name'], held['data'])

    def publish(self, name, data):
        """Number the event, keep it for resume, and queue it for every live phone."""
        self.seq += 1
        frame = dumps({'t': 'evt', 'seq': self.seq, 'event': name, 'data': data, 'ts': wire.now_ms()})
        if len(frame.encode('utf-8')) > MAX_EVENT:
            trimmed = {k: data[k] for k in ('chat_id', 'run_id', 'id') if isinstance(data, dict) and k in data}
            frame = dumps({'t': 'evt', 'seq': self.seq, 'event': name, 'data': {**trimmed, 'trimmed': True},
                           'ts': wire.now_ms()})
            log('event %s above 1 MB, trimmed' % name)
        self._keep_and_send(frame)

    def _keep_and_send(self, frame):
        """frame: the event's text, or a function of the receiving device id that makes it (remote.devices)."""
        now = time.monotonic()
        self.buffer.append((self.seq, now, frame))
        while len(self.buffer) > REPLAY_HARD or (len(self.buffer) > REPLAY_EVENTS
                                                 and now - self.buffer[0][1] > REPLAY_SECONDS):
            self.buffer.popleft()
        for conn in list(self.conns):
            if conn.live:
                conn.send(frame if isinstance(frame, str) else frame(conn.device))

    def bridge_event(self, name, data):
        self.flush_batch()
        self.publish(name, data)

    def devices_event(self):
        """remote.devices carries the same array as the remote.devices method (v0.3 item 7), so each phone's copy
        marks that phone as `current`; the list is the one at the time of the event, for resume too."""
        self.flush_batch()
        self.seq += 1
        seq, ts, rows = self.seq, wire.now_ms(), self.registry.listing()

        def frame(device_id):
            data = [dict(row, current=row['device_id'] == device_id) for row in rows]
            return dumps({'t': 'evt', 'seq': seq, 'event': 'remote.devices', 'data': data, 'ts': ts})

        self._keep_and_send(frame)

    def can_resume(self, resume):
        if not isinstance(resume, dict) or resume.get('epoch') != self.epoch:
            return False
        seq = resume.get('seq')
        if type(seq) is not int or seq < 0 or seq > self.seq:
            return False
        oldest = self.buffer[0][0] if self.buffer else self.seq + 1
        return seq + 1 >= oldest

    # -- connections --------------------------------------------------------------------------------------------------

    async def handle(self, reader, writer):
        sock = writer.get_extra_info('socket')
        if sock is not None:
            try:
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except OSError:
                pass
        self.counter += 1
        number = self.counter
        peer = writer.get_extra_info('peername')
        if not self.admit(peer[0] if peer else None):
            log('conn#%d refused: more than %d handshakes a minute from one address' % (number, HANDSHAKES_PER_MINUTE))
            writer.write(b'HTTP/1.1 429 Too Many Requests\r\nRetry-After: 60\r\nContent-Length: 0\r\n'
                         b'Connection: close\r\n\r\n')
            try:
                await writer.drain()
            except (ConnectionError, OSError):
                pass
            writer.close()
            return
        ws = await wire.server_handshake(reader, writer, max_message=HARD_MESSAGE)
        if ws is None:
            log('conn#%d refused at the WebSocket handshake' % number)
            return
        conn = Conn(self, ws, number)
        busy = len(self.conns) >= MAX_CONNECTIONS
        self.conns.add(conn)
        conn.writer = asyncio.create_task(conn.writer_loop())
        watchdog = asyncio.create_task(self.watchdog(conn))
        if busy:
            log('conn#%d refused: %d connections are open' % (number, MAX_CONNECTIONS))
            conn.bye('busy')
        else:
            conn.send({'t': 'challenge', 'v': 1, 'bid': self.bid, 'nonce': conn.nonce, 'time': wire.now_ms()})
            log('conn#%d open' % number)
        try:
            while True:
                message = await ws.recv()
                if message is None:
                    break
                if isinstance(message, bytes):
                    conn.close(wire.CLOSE_UNSUPPORTED, 'text frames only')
                    continue
                await self.on_text(conn, message)
        finally:
            self.conns.discard(conn)
            conn.live = False
            if conn.device and self.by_device.get(conn.device) is conn:
                del self.by_device[conn.device]
                # S-05 (claude-w, 10:49): the device's unlock ends with its last connection (a connection replaced by
                # a newer one is not the last: by_device then names the newer one)
                if self.unlocked.pop(conn.device, None) is not None:
                    log('device %s: its last connection closed, so its unlock ended' % short(conn.device))
            if conn.pairing is not None and not conn.pairing.done():
                conn.pairing.cancel()  # X-1: the phone left before the person answered
            watchdog.cancel()
            if conn.closing is None:
                conn.closing = (ws.close_code or wire.CLOSE_NORMAL, '')
                conn.wake.set()
            try:
                await asyncio.wait_for(conn.writer, 3)
            except (asyncio.TimeoutError, TimeoutError, asyncio.CancelledError, ConnectionError, OSError):
                conn.writer.cancel()
            if not ws.closed:
                ws.abort()
            log('conn#%d closed (%s)' % (number, ws.close_code))

    def admit(self, address):
        """C6: at most HANDSHAKES_PER_MINUTE connections a minute from one source address. Loopback (this Mac) is
        exempt unless --limit-loopback: the limit guards the LAN listener."""
        if not address or (wire.address_kind(address) == 'loopback' and not self.limit_loopback):
            return True
        now = time.monotonic()
        times = self.handshakes.setdefault(address, deque())
        while times and now - times[0] > 60:
            times.popleft()
        if len(times) >= HANDSHAKES_PER_MINUTE:
            return False
        times.append(now)
        return True

    async def watchdog(self, conn):
        step = max(0.2, min(5.0, self.idle_timeout / 4))
        while True:
            await asyncio.sleep(step)
            if conn.confirming:  # X-1: the person has up to two minutes; the confirmation's own timeout ends the wait
                continue
            now = time.monotonic()
            if conn.device is None and now - conn.opened > AUTH_SECONDS:
                log('conn#%d did not authenticate in time' % conn.number)
                conn.close(wire.CLOSE_POLICY, 'authenticate first')
                return
            if now - conn.ws.last_received > self.idle_timeout:
                log('conn#%d silent for %ds, closing' % (conn.number, self.idle_timeout))
                conn.close(wire.CLOSE_GOING_AWAY, 'silent too long')
                return

    async def on_text(self, conn, text):
        size = len(text.encode('utf-8'))
        try:
            message = loads(text)
        except ValueError:
            message = None
        if size > MAX_REQUEST:
            # v0.3 item 6: a frame over 128 KB that parses and has an id gets `res` `too_large`; one that does not
            # gets `bye` `too_large`, and the connection closes.
            ident = message.get('id') if isinstance(message, dict) else None
            if conn.device is not None and wire.valid_id(ident):
                log('conn#%d request of %d bytes refused: too_large' % (conn.number, size))
                self.refuse(conn, ident, 'too_large')
            else:
                log('conn#%d unreadable frame of %d bytes: bye too_large' % (conn.number, size))
                conn.bye('too_large')
            return
        if not isinstance(message, dict):
            log('conn#%d sent a frame that is not a JSON object' % conn.number)
            conn.close(wire.CLOSE_BAD_DATA, 'not a JSON object')
            return
        kind = message.get('t')
        if conn.device is None:
            if conn.confirming:
                log('conn#%d sent %s while its pairing waits for the Mac; ignored' % (conn.number, str(kind)[:16]))
                return
            if kind == 'pair':
                self.on_pair(conn, message)
            elif kind == 'hello':
                self.on_hello(conn, message)
            else:
                log('conn#%d sent %s before authenticating; closing' % (conn.number, str(kind)[:16]))
                conn.close(wire.CLOSE_POLICY, 'authenticate first')
            return
        if kind == 'req':
            task = asyncio.create_task(self.on_req(conn, message))
            self.requests.add(task)
            task.add_done_callback(self.requests.discard)
        else:
            log('conn#%d ignored a %s frame' % (conn.number, str(kind)[:16]))

    def on_pair(self, conn, message):
        if message.get('v') != 1:
            return conn.bye('bad_version')
        code = message.get('code')
        offer = self.pairing
        ok = False
        if offer is not None and not offer['used'] and time.monotonic() < offer['expires'] and \
                offer['tries'] < PAIRING_TRIES and isinstance(code, str):
            ok = hmac.compare_digest(code.encode('utf-8'), offer['code'].encode('ascii'))
        if not ok:
            if offer is not None and not offer['used']:
                offer['tries'] += 1
            log('conn#%d pairing refused: wrong, used or expired code' % conn.number)
            return conn.bye('bad_code')
        try:
            device_key, approve_key = message['device_key'], message['approve_key']
            transcript = wire.t_pair(self.bid, conn.nonce, self.pin, code, device_key, approve_key)
            good = wire.verify(wire.decode_point(wire.b64u_decode(device_key)), transcript,
                               wire.b64u_decode(message['sig'])) and \
                wire.verify(wire.decode_point(wire.b64u_decode(approve_key)), transcript,
                            wire.b64u_decode(message['approve_sig']))
        except (KeyError, ValueError, TypeError):
            good = False
        if not good:
            offer['tries'] += 1
            log('conn#%d pairing refused: bad signature' % conn.number)
            return conn.bye('bad_signature')
        offer['used'] = True  # spent from here: a second phone with the same link is refused while the person decides
        device = message.get('device') if isinstance(message.get('device'), dict) else {}
        # X-1: nothing is stored and `paired` waits until the person confirms on the Mac that the phone shows the same
        # six digits (they come from T_pair, which both signatures cover)
        conn.confirming = True
        conn.pairing = asyncio.create_task(self.confirm_pairing(conn, device, device_key, approve_key,
                                                                wire.sas_code(transcript)))
        self.requests.add(conn.pairing)
        conn.pairing.add_done_callback(self.requests.discard)

    async def confirm_pairing(self, conn, device, device_key, approve_key, sas):
        """X-1. The Mac shows the code; the person confirms that the phone shows the same (or cancels, or does not
        answer for two minutes: `bye` `bad_code`, and the pairing code stays spent). Only then is the phone stored,
        and `paired`, then `welcome`, sent."""
        log('conn#%d pairing code %s: confirm on the Mac' % (conn.number, sas))  # the one log line with a code
        if self.on_pairing_code:
            self.on_pairing_code(sas)
        try:
            confirmed = await self.confirmer.ask(sas)
        except asyncio.CancelledError:
            log('conn#%d pairing stopped: the phone went away before it was confirmed' % conn.number)
            raise
        finally:
            conn.confirming = False
            if conn.ws is not None:  # the wait was not silence from a phone that is still there
                conn.ws.last_received = time.monotonic()
        if not confirmed:
            log('conn#%d pairing not confirmed on the Mac: bad_code' % conn.number)
            return conn.bye('bad_code', PAIR_REFUSED)
        if conn.closing is not None or conn not in self.conns:
            return
        record = self.registry.add(device, device_key, approve_key)
        log('conn#%d paired device %s' % (conn.number, short(record['device_id'])))
        conn.send({'t': 'paired', 'device_id': record['device_id']})
        self.authenticate(conn, record, None)
        self.devices_event()  # after the welcome, so the new phone gets it too

    def on_hello(self, conn, message):
        if message.get('v') != 1:
            return conn.bye('bad_version')
        device_id = message.get('device_id')
        if isinstance(device_id, str) and device_id in self.registry.revoked:
            return conn.bye('revoked')
        record = self.registry.get(device_id)
        if record is None:
            log('conn#%d hello from an unknown device' % conn.number)
            return conn.bye('unknown_device')
        try:
            good = wire.verify(wire.decode_point(wire.b64u_decode(record['device_key'])),
                               wire.t_hello(self.bid, device_id, conn.nonce, self.pin),
                               wire.b64u_decode(message.get('sig')))
        except (ValueError, TypeError):
            good = False
        if not good:
            log('conn#%d hello with a bad signature' % conn.number)
            return conn.bye('bad_signature')
        self.registry.touch(device_id, message.get('app'))
        self.authenticate(conn, record, message.get('resume'))

    def authenticate(self, conn, record, resume):
        """Welcome the phone, replay what it missed, then make it live; no await in between, so no live event can
        overtake a replayed one (section 3.3)."""
        device_id = record['device_id']
        older = self.by_device.get(device_id)
        if older is not None and older is not conn:
            log('conn#%d replaces conn#%d for device %s' % (conn.number, older.number, short(device_id)))
            older.bye('replaced')
        conn.device = device_id
        self.by_device[device_id] = conn
        self.flush_batch()
        resumed = self.can_resume(resume)
        conn.send({'t': 'welcome', 'v': 1, 'epoch': self.epoch, 'seq': self.seq, 'resumed': resumed,
                   'bridge': {'version': BRIDGE_VERSION, 'name': self.name},
                   'pebble': {'running': self.sim.running, 'version': PEBBLE_VERSION},
                   'methods': list(METHODS), 'elevated': list(ELEVATED), 'unlock_seconds': self.unlock_seconds,
                   'limits': {'max_request': MAX_REQUEST, 'max_frame': MAX_FRAME}})
        replayed = 0
        if resumed:
            for seq, _, frame in self.buffer:
                if seq > resume['seq']:
                    conn.send(frame if isinstance(frame, str) else frame(device_id))
                    replayed += 1
        conn.live = True
        log('conn#%d welcome device %s resumed=%s replayed=%d' % (conn.number, short(device_id), resumed, replayed))

    # -- requests -----------------------------------------------------------------------------------------------------

    def refuse(self, conn, request_id, code, error=None):
        conn.send({'t': 'res', 'id': request_id, 'ok': False, 'error': error or ERRORS[code], 'code': code})

    def workspace_class(self, path):
        """What a `workspace` or `path` asks for: 'none' (null: the Companion), 'known' (a project a conversation on
        the Mac uses) or 'new'. Anything that is not null or a known string is 'new', so it fails closed."""
        if path is None or path == '':
            return 'none'
        if isinstance(path, str) and path in self.sim.known_workspaces():
            return 'known'
        return 'new'

    def needs_proof(self, method, params):
        """Section 3.6 (v0.2) with C1's remote.unlock and v0.5's opening methods; `setting` by its key's class (an
        unclassified key too); and v0.5's new folder: `set_workspace` and `new_chat` need a proof only for a folder no
        conversation uses yet (a known project, or null for the Companion, needs the unlock alone). `new_chat` has the
        same rule as `set_workspace`: otherwise it would be a way around it."""
        if method in ELEVATED_ALWAYS:
            return True
        if method == 'setting':
            # A key that is not a string cannot be classified, and looking it up raised TypeError (no answer at all):
            # it needs a proof, as an unclassified key does (security review 2026-10-30, M-2).
            key = params.get('key')
            return not isinstance(key, str) or SETTING_CLASSES.get(key, 'elevated') == 'elevated'
        if method in ('set_workspace', 'new_chat'):
            return self.workspace_class(params.get('path' if method == 'set_workspace' else 'workspace')) == 'new'
        return False

    def remember_made(self, device, path):
        """v0.6: this device just made the folder at `path`. Old ones are forgotten, and at most MADE_FOLDERS_KEPT are
        kept for one device (the oldest go first)."""
        now = time.monotonic()
        mine = self.made.setdefault(device, {})
        for old in [p for p, at in mine.items() if now - at > MADE_FOLDER_SECONDS]:
            del mine[old]
        mine.pop(path, None)
        mine[path] = now
        while len(mine) > MADE_FOLDERS_KEPT:
            del mine[next(iter(mine))]

    def made_by(self, device, path):
        """v0.6, item 2: whether this device made the folder at `path` (exactly that path) in the last ten minutes."""
        at = self.made.get(device, {}).get(path) if isinstance(path, str) else None
        return at is not None and time.monotonic() - at <= MADE_FOLDER_SECONDS

    def made_here(self, device, method, params):
        """v0.6, item 2: `set_workspace` and `new_chat` with exactly the path of a folder this device made in the last ten
        minutes need only the unlock, as a project a conversation uses does: the person already proved themselves for
        that very folder when they made it. Nothing else changes: the folder must still be one `remote.folders` would
        list (`policy`), and another device, another path or later than ten minutes gets `proof_required`."""
        if method not in ('set_workspace', 'new_chat'):
            return False
        return self.made_by(device, params.get('path' if method == 'set_workspace' else 'workspace'))

    def check_proof(self, conn, message, method, reused, idem):
        """Section 3.6 and v0.3: `ts` within 60 s of the Mac's clock, an id unused on this connection, a signature not
        accepted from this device in the last 120 s on any connection (C2, keyed by the signature's r, so the
        (r, n-s) twin is caught too), and the approve key's signature over T_proof, which v0.3 binds to this
        connection's nonce and the call's idem. An accepted proof unlocks the device (C1)."""
        proof = message.get('proof')
        if not isinstance(proof, dict) or reused:
            return False
        ts = proof.get('ts')
        if type(ts) is not int or abs(wire.now_ms() - ts) > PROOF_WINDOW_MS:
            return False
        record = self.registry.get(conn.device)
        if record is None:
            return False
        try:
            signature = wire.b64u_decode(proof.get('sig'))
            r, _ = wire.der_decode_signature(signature)
            if self.proof_version == 2:
                transcript = wire.t_proof_v02(self.bid, conn.device, self.epoch, message['id'], method,
                                              message['params_json'], ts)
            else:
                transcript = wire.t_proof(self.bid, conn.device, self.epoch, conn.nonce, message['id'], idem, method,
                                          message['params_json'], ts)
            approve_key = wire.decode_point(wire.b64u_decode(record['approve_key']))
        except (ValueError, TypeError):
            return False
        now = time.monotonic()
        for key in [k for k, at in self.proofs.items() if now - at > PROOF_MEMORY_SECONDS]:
            del self.proofs[key]
        if (conn.device, r) in self.proofs:
            log('conn#%d a proof accepted before was sent again (C2)' % conn.number)
            return False
        if not wire.verify(approve_key, transcript, signature):
            return False
        self.proofs[(conn.device, r)] = now
        self.unlocked[conn.device] = (now + self.unlock_seconds, wire.now_ms() + self.unlock_seconds * 1000)
        return True

    def is_unlocked(self, device):
        until = self.unlocked.get(device)
        return until is not None and until[0] > time.monotonic()

    def policy(self, method, params):
        """The bridge's own check after the allowlist and the proof (section 3.7, proposal v0.5): a folder no
        conversation uses yet is connected only when `remote.folders` would list it. (A call with such a folder and
        no proof never gets here: `needs_proof` answers `proof_required` first, so a phone that is not unlocked learns
        nothing about the Mac's folders from the answer.)"""
        if method in ('new_chat', 'set_workspace'):
            path = params.get('path' if method == 'set_workspace' else 'workspace')
            if self.workspace_class(path) == 'new' and not self.folders.listable(path):
                return WORKSPACE_REFUSED
        return None

    async def on_req(self, conn, message):
        started = time.perf_counter()
        request_id = message.get('id')
        if not wire.valid_id(request_id):  # v0.3 item 2
            log('conn#%d a request id outside [A-Za-z0-9_-]{1,64}: bad_request' % conn.number)
            return self.refuse(conn, request_id if isinstance(request_id, str) and len(request_id) <= 64 else None,
                               'bad_request', ID_REFUSED)
        method = message.get('method')
        if not isinstance(method, str):
            return self.refuse(conn, request_id, 'bad_request')
        method_label = method if method in METHOD_SET else '?'
        bucket = self.buckets.setdefault(conn.device, TokenBucket())
        if not bucket.take():
            log('conn#%d %s refused: rate_limited' % (conn.number, method_label))
            return self.refuse(conn, request_id, 'rate_limited')
        reused = request_id in conn.used_ids
        conn.used_ids.add(request_id)
        if method not in METHOD_SET:
            log('conn#%d a method outside the allowlist refused: not_allowed' % conn.number)
            return self.refuse(conn, request_id, 'not_allowed')
        idem = message.get('idem')
        signed = 'params_json' in message or 'proof' in message
        if idem is not None and not wire.valid_id(idem):
            return self.refuse(conn, request_id, 'bad_request', RETRY_KEY_REFUSED)
        if idem is None and (signed or method not in READ_ONLY):  # v0.3 item 4 (and idem is a T_proof line)
            log('conn#%d %s refused: no idem' % (conn.number, method))
            return self.refuse(conn, request_id, 'bad_request', RETRY_KEY_REFUSED)
        proven = False
        if 'params_json' in message:
            if not isinstance(message['params_json'], str):
                return self.refuse(conn, request_id, 'bad_request')
            if 'proof' not in message:
                log('conn#%d %s refused: proof_required' % (conn.number, method))
                return self.refuse(conn, request_id, 'proof_required')
            if not self.check_proof(conn, message, method, reused, idem):
                log('conn#%d %s refused: bad_proof' % (conn.number, method))
                return self.refuse(conn, request_id, 'bad_proof')
            try:
                params = loads(message['params_json'])
            except ValueError:
                params = None
            if not isinstance(params, dict):
                return self.refuse(conn, request_id, 'bad_request')
            proven = True
        else:
            if 'proof' in message:
                return self.refuse(conn, request_id, 'bad_request',
                                   'A Face ID confirmation must come with its request as signed text.')
            params = message.get('params', {})
            if params is None:
                params = {}
            if not isinstance(params, dict):
                return self.refuse(conn, request_id, 'bad_request')
            if reused:
                return self.refuse(conn, request_id, 'bad_request')
            if self.needs_proof(method, params) and not self.made_here(conn.device, method, params):
                log('conn#%d %s refused: proof_required' % (conn.number, method))
                return self.refuse(conn, request_id, 'proof_required')
        if not proven and method not in UNLOCK_FREE and not self.is_unlocked(conn.device):  # C1
            log('conn#%d %s refused: unlock_required' % (conn.number, method))
            return self.refuse(conn, request_id, 'unlock_required')
        refusal = self.policy(method, params)
        if refusal:
            log('conn#%d %s refused by the phone policy: not_allowed' % (conn.number, method))
            return self.refuse(conn, request_id, 'not_allowed', refusal)
        future = None
        if idem is not None:
            self.sweep_idem()
            entry = self.idem.get((conn.device, idem))
            if entry is not None:
                if entry['method'] != method:
                    return self.refuse(conn, request_id, 'bad_request', 'That retry key belongs to another request.')
                answer = await asyncio.shield(entry['future'])
                conn.send({'t': 'res', 'id': request_id, **answer})
                log('conn#%d %s answered again from its retry key (done once)' % (conn.number, method))
                return
            future = asyncio.get_running_loop().create_future()
            self.idem[(conn.device, idem)] = {'method': method, 'future': future, 'at': time.monotonic()}
        after = None
        try:
            answer, after = await self.execute(conn, method, params)
        except Exception as exc:  # never leave a retry waiting forever
            log('conn#%d %s failed inside the bridge (%s)' % (conn.number, method, type(exc).__name__))
            answer = {'ok': False, 'error': DEFECT_TEXT, 'code': 'bad_request'}
        if future is not None:
            future.set_result(answer)
        frame = dumps({'t': 'res', 'id': request_id, **answer})
        if len(frame.encode('utf-8')) > MAX_FRAME:
            self.refuse(conn, request_id, 'too_large')
        else:
            conn.send(frame)
        log('conn#%d %s %s %.1f ms' % (conn.number, method, 'ok' if answer.get('ok') else
                                       'refused ' + str(answer.get('code', 'pebble')),
                                       (time.perf_counter() - started) * 1000))
        if after is not None:
            after()

    def sweep_idem(self):
        now = time.monotonic()
        for key in [k for k, e in self.idem.items() if now - e['at'] > IDEM_SECONDS and e['future'].done()]:
            del self.idem[key]

    async def execute(self, conn, method, params):
        """(answer, after): the answer to send, and what to do once it is sent."""
        if method == 'remote.screenshot':
            return await self.screenshot(params)
        if method == 'remote.folders':  # reads the disk: in a thread, so a slow folder never holds up the other phones
            try:
                return await asyncio.wait_for(asyncio.to_thread(self.remote, conn, method, params), CALL_TIMEOUT)
            except (asyncio.TimeoutError, TimeoutError):
                return {'ok': False, 'error': ERRORS['timeout'], 'code': 'timeout'}, None
        if method == 'remote.folder_create':  # v0.6: writes to the disk: in a thread, as the listing is
            try:
                made = await asyncio.wait_for(
                    asyncio.to_thread(self.folders.create, params.get('parent'), params.get('name')), CALL_TIMEOUT)
            except FolderRefused as exc:
                return {'ok': False, 'error': exc.words, **({'code': exc.code} if exc.code else {})}, None
            except (asyncio.TimeoutError, TimeoutError):
                return {'ok': False, 'error': ERRORS['timeout'], 'code': 'timeout'}, None
            self.remember_made(conn.device, made['path'])
            log('device %s made a folder' % short(conn.device))  # content-free: the Mac's notice would name it (C7)
            return {'ok': True, 'result': made}, None
        if method.startswith('remote.'):
            return self.remote(conn, method, params)
        if not self.sim.running:
            return {'ok': False, 'error': ERRORS['pebble_offline'], 'code': 'pebble_offline'}, None
        try:
            result = await asyncio.wait_for(self.sim.call(method, params), CALL_TIMEOUT)
            return {'ok': True, 'result': result}, None
        except (asyncio.TimeoutError, TimeoutError):
            return {'ok': False, 'error': ERRORS['timeout'], 'code': 'timeout'}, None
        except PebbleError as exc:
            answer = {'ok': False, 'error': exc.message}
            if exc.code:
                answer['code'] = exc.code
            return answer, None

    # -- remote.* (section 3.8) -----------------------------------------------------------------------------------------

    def remote(self, conn, method, params):
        def bad(words=None):
            return {'ok': False, 'error': words or ERRORS['bad_request'], 'code': 'bad_request'}, None

        def ok(result, after=None):
            return {'ok': True, 'result': result}, after

        if method == 'remote.ping':
            ts = params.get('ts')
            if isinstance(ts, bool) or not isinstance(ts, (int, float)):
                return bad()
            return ok({'ts': ts, 'mac_ts': wire.now_ms()})
        if method == 'remote.status':
            return ok({'mac': {'name': self.name, **self.mac},
                       'pebble': {'running': self.sim.running, 'version': PEBBLE_VERSION},
                       'bridge': {'version': BRIDGE_VERSION, 'epoch': self.epoch, 'endpoints': list(self.endpoints)}})
        if method == 'remote.devices':
            return ok(self.registry.listing(current=conn.device))
        if method == 'remote.revoke_device':
            target = params.get('device_id')
            if not isinstance(target, str) or not self.registry.revoke(target):
                return bad("That iPhone isn't paired with this Mac.")
            log('device %s removed' % short(target))
            self.unlocked.pop(target, None)
            self.made.pop(target, None)
            self.devices_event()
            victim = self.by_device.pop(target, None)

            def end():
                if victim is not None:
                    victim.bye('revoked')
            return ok({}, end)
        if method == 'remote.lock':  # S-05 (claude-w, 10:49): ends this device's unlock at once; a read, {} to {}
            if self.unlocked.pop(conn.device, None) is not None:
                log('device %s locked itself' % short(conn.device))
            return ok({})
        if method == 'remote.unlock':
            # Reached only with an accepted proof, which has just unlocked this device (C1)
            return ok({'unlocked_until': self.unlocked[conn.device][1], 'unlock_seconds': self.unlock_seconds})
        if method == 'remote.folders':  # v0.5: needs the unlock (it is not one of C1's reads); no Face ID
            try:
                return ok(self.folders.listing(params.get('path')))
            except FolderRefused as exc:
                return {'ok': False, 'error': exc.words, **({'code': exc.code} if exc.code else {})}, None
        if method == 'remote.keep_awake':  # R3: on by default, on battery too; no Face ID to change it
            if type(params.get('on')) is not bool:
                return bad()
            if self.mac['keep_awake'] != params['on']:
                self.mac['keep_awake'] = params['on']
                self.mac_event(force=True)
            return ok({'keep_awake': self.mac['keep_awake']})
        if method in ('remote.chat_tail', 'remote.chat_before'):
            limit = params.get('limit', 50)
            if type(limit) is not int or not 1 <= limit <= 500 or not isinstance(params.get('id'), str):
                return bad()
            if not self.sim.running:
                return {'ok': False, 'error': ERRORS['pebble_offline'], 'code': 'pebble_offline'}, None
            try:
                chat = self.sim.chat(params['id'])
            except PebbleError as exc:
                return {'ok': False, 'error': exc.message}, None
            messages = chat['messages']
            if method == 'remote.chat_tail':
                chat = loads(dumps(chat))
                chat['messages'] = chat['messages'][-limit:]
                chat['has_older'] = len(messages) > limit
                return ok(chat)
            index = next((i for i, m in enumerate(messages) if m['id'] == params.get('before')), None)
            if index is None:
                return {'ok': False, 'error': 'Message not found in this conversation.'}, None
            return ok({'messages': loads(dumps(messages[max(0, index - limit):index])),
                       'has_older': index - limit > 0})
        return {'ok': False, 'error': ERRORS['not_allowed'], 'code': 'not_allowed'}, None

    def mac_event(self, force=False):
        now = time.monotonic()
        if force or now - self.mac_emitted >= 60:
            self.mac_emitted = now
            self.bridge_event('remote.mac', dict(self.mac))

    # -- C3: remote.screenshot ------------------------------------------------------------------------------------------

    DISPLAYS = ((0, 1512, 982), (1, 2560, 1440))  # a MacBook's built-in screen and an external display

    async def screenshot(self, params):
        """C3: `{display: <index>|null}` -> `{taken_at, displays:[{index, width, height, format, data}]}`. Never a real
        capture: each display is a generated test pattern (a PNG written with zlib, made a JPEG by the built-in sips),
        made once and kept in memory. The Mac's notice is this log line."""
        wanted = params.get('display')
        if wanted is not None and (type(wanted) is not int or wanted < 0):
            return {'ok': False, 'error': ERRORS['bad_request'], 'code': 'bad_request'}, None
        if not self.sim.running:
            return {'ok': False, 'error': ERRORS['pebble_offline'], 'code': 'pebble_offline'}, None
        if not self.screen_recording:
            return {'ok': False, 'error': "Pebble can't see the screen. Allow Screen Recording for Pebble in System "
                                         'Settings › Privacy & Security, then try again.'}, None
        if wanted is not None and wanted not in [index for index, _, _ in self.DISPLAYS]:
            return {'ok': False, 'error': 'This Mac has no display %d.' % wanted}, None
        if self.screens is None:
            try:
                self.screens = await asyncio.to_thread(make_test_screens, self.DISPLAYS, self.state_dir)
            except (RuntimeError, OSError, subprocess.SubprocessError):
                log('the test pattern could not be made (sips)')
                return {'ok': False, 'error': "Pebble couldn't take a screenshot. Try again."}, None
        log('a screenshot was taken from the phone (test pattern; the Mac shows a notice)')
        return {'ok': True, 'result': {'taken_at': wire.now_ms(), 'displays': [
            {'index': index, 'width': width, 'height': height, 'format': 'jpeg',
             'data': __import__('base64').b64encode(self.screens[index]).decode('ascii')}
            for index, width, height in self.DISPLAYS if wanted is None or index == wanted]}}, None

    async def housekeeping(self):
        while True:
            await asyncio.sleep(60)
            self.sweep_idem()
            if not self.mac['on_power'] and self.mac['battery_percent'] > 5:
                self.mac['battery_percent'] -= 1
                self.mac_event()

    def toggle_pebble(self):
        self.sim.running = not self.sim.running
        log('simulated Pebble %s' % ('started' if self.sim.running else 'stopped'))
        self.bridge_event('remote.pebble', {'running': self.sim.running, 'version': PEBBLE_VERSION})


# =====================================================================================================================
# CLI
# =====================================================================================================================

def _command(*args):
    try:
        done = subprocess.run(list(args), capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
        return done.stdout.strip() if done.returncode == 0 else ''
    except (OSError, subprocess.SubprocessError):
        return ''


def lan_ipv4():
    for interface in ('en0', 'en1'):
        address = _command('/usr/sbin/ipconfig', 'getifaddr', interface)
        if address:
            return address
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(('192.0.2.1', 9))  # no packet is sent
            return probe.getsockname()[0]
    except OSError:
        return None


def tailnet_ipv4s():
    found = []
    for line in _command('/sbin/ifconfig').splitlines():
        match = re.match(r'\s*inet (100\.(\d+)\.\d+\.\d+) ', line)
        if match and 64 <= int(match.group(2)) <= 127:
            found.append(match.group(1))
    return found


async def serve(args):
    global QUIET
    QUIET = args.quiet
    state_dir = os.path.abspath(args.state_dir)
    identity = Identity(state_dir)
    registry = Registry(os.path.join(state_dir, 'devices.json'))
    name = args.name or _command('/usr/sbin/scutil', '--get', 'ComputerName') or socket.gethostname() or 'Mac'
    folders_root = None
    if args.pair_confirm_timeout <= 0 or args.pair_confirm_delay < 0:
        raise SystemExit('mock: --pair-confirm-timeout must be above 0 and --pair-confirm-delay at least 0')
    if args.folders_root:
        folders_root = os.path.abspath(os.path.expanduser(args.folders_root))
        if not os.path.isdir(folders_root):
            raise SystemExit('mock: --folders-root must be an existing folder')
        log('remote.folders lists a test tree (--folders-root), not the home folder')
    bridge = Bridge(identity, registry, name=name, speed=args.speed, on_power=not args.battery,
                    idle_timeout=args.idle_timeout, unlock_seconds=args.unlock_seconds,
                    proof_version=args.proof_version, screen_recording=not args.no_screen_recording,
                    limit_loopback=args.limit_loopback, state_dir=state_dir, folders_root=folders_root,
                    pair_confirm=args.pair_confirm, pair_confirm_timeout=args.pair_confirm_timeout,
                    pair_confirm_delay=args.pair_confirm_delay)
    context = identity.tls_context()
    if args.lan:
        lan = lan_ipv4()
        if not lan:
            raise SystemExit('mock: no LAN address found (is Wi-Fi on?)')
        if wire.address_kind(lan) != 'private':  # C6: the LAN listener uses private addresses only
            raise SystemExit('mock: the LAN address is not a private one, so the mock will not listen there (C6)')
        tailnet = [ip for ip in tailnet_ipv4s() if ip != lan]
        hosts = [lan] + tailnet + ['127.0.0.1']  # loopback too, for checks on this Mac; never put in the link
        local = _command('/usr/sbin/scutil', '--get', 'LocalHostName')
        names = [lan] + ([local + '.local'] if local else []) + tailnet
    else:
        if args.host != 'localhost' and wire.address_kind(args.host) not in ('loopback', 'private', 'tailnet'):
            raise SystemExit('mock: --host must be a loopback, private or Tailscale address; never a public or '
                             'wildcard one (C6)')
        hosts, names = [args.host], [args.host]
    servers = []
    port = args.port
    for host in hosts:
        server = await asyncio.start_server(bridge.handle, host, port, ssl=context, ssl_handshake_timeout=10,
                                            limit=1 << 16)
        servers.append(server)
        port = server.sockets[0].getsockname()[1]
    bridge.endpoints = [wire.format_endpoint(n, port) for n in dict.fromkeys(names)]
    print('PORT=%d' % port, flush=True)
    print('PIN=' + bridge.pin, flush=True)
    print('BID=' + bridge.bid, flush=True)
    print('ENDPOINTS=' + ','.join(bridge.endpoints), flush=True)
    print('PID=%d' % os.getpid(), flush=True)
    log('listening on %s port %d (TLS 1.3, pin %s...)' % (', '.join(hosts), port, bridge.pin[:8]))

    def show_link(link):
        print('PAIRING_LINK=' + link, flush=True)
        if args.copy:
            try:
                subprocess.run(['/usr/bin/pbcopy'], input=link.encode(), timeout=5, check=False)
                log('pairing link copied to the clipboard')
            except (OSError, subprocess.SubprocessError):
                log('could not copy the pairing link')

    def show_code(code):  # X-1: for a script or a person watching; the phone shows the same six digits
        print('PAIRING_CODE=' + code, flush=True)

    bridge.on_link = show_link
    bridge.on_pairing_code = show_code
    if args.print_pairing or args.copy:
        bridge.open_pairing()
    bonjour = None
    if args.bonjour:
        bonjour = subprocess.Popen(['/usr/bin/dns-sd', '-R', bridge.bid, '_pebble-remote._tcp', 'local', str(port), 'v=1',
                                    'bid=' + bridge.bid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   stdin=subprocess.DEVNULL)
        log('advertising _pebble-remote._tcp on port %d, instance named by the bridge id (C6)' % port)
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    loop.add_signal_handler(signal.SIGUSR1, bridge.open_pairing)
    loop.add_signal_handler(signal.SIGUSR2, bridge.toggle_pebble)
    loop.add_signal_handler(signal.SIGINT, stop.set)
    loop.add_signal_handler(signal.SIGTERM, stop.set)
    housekeeping = asyncio.create_task(bridge.housekeeping())
    print('READY=1', flush=True)
    try:
        await stop.wait()
    finally:
        housekeeping.cancel()
        log('stopping')
        for conn in list(bridge.conns):
            conn.close(wire.CLOSE_GOING_AWAY, 'the bridge is stopping')
        await asyncio.sleep(0.2)
        for server in servers:
            server.close()
        if bonjour is not None:
            bonjour.terminate()
            try:
                bonjour.wait(3)
            except subprocess.TimeoutExpired:
                bonjour.kill()


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Pebble Remote mock bridge (contract v0.3 and proposal v0.5) with a simulated Pebble.')
    parser.add_argument('--host', default='127.0.0.1', help='address to listen on (default 127.0.0.1)')
    parser.add_argument('--port', type=int, default=0, help='port (0 = ephemeral; printed as PORT=)')
    parser.add_argument('--state-dir', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'state'),
                        help='TLS key, certificate, bridge id and paired phones (default bridge-mock/state)')
    parser.add_argument('--name', help="the Mac's name shown on the phone (default: this Mac's name)")
    parser.add_argument('--speed', type=float, default=1.0, help='simulated Pebble speed (2 = twice as fast)')
    parser.add_argument('--print-pairing', action='store_true', help='open pairing and print PAIRING_LINK=...')
    parser.add_argument('--copy', action='store_true', help='also copy the pairing link with pbcopy')
    parser.add_argument('--bonjour', action='store_true', help='advertise _pebble-remote._tcp with dns-sd -R')
    parser.add_argument('--lan', action='store_true',
                        help='listen on the LAN address (and any Tailscale 100.x address) for a real iPhone')
    parser.add_argument('--battery', action='store_true', help='simulate a Mac on battery')
    parser.add_argument('--idle-timeout', type=float, default=45.0, help='close a silent connection after this long')
    parser.add_argument('--unlock-seconds', type=int, default=UNLOCK_SECONDS,
                        help='C1: how long an accepted Face ID proof lets the phone act (default 900)')
    parser.add_argument('--proof-version', type=int, choices=(2, 3),
                        default=3 if os.environ.get('PEBBLE_MOCK_PROOF_VERSION') != '2' else 2,
                        help="T_proof as contract v0.3 has it (default), or v0.2's (no nonce, no idem) for one round "
                             'while a client still signs that (also PEBBLE_MOCK_PROOF_VERSION=2)')
    parser.add_argument('--no-screen-recording', action='store_true',
                        help='C3: answer remote.screenshot as a Mac without Screen Recording permission does')
    parser.add_argument('--limit-loopback', action='store_true',
                        help='C6: apply the 10-handshakes-a-minute limit to 127.0.0.1 too (for tests)')
    parser.add_argument('--pair-confirm', choices=('auto', 'ask', 'refuse'), default='auto',
                        help="X-1: how the Mac confirms a pairing after `pair` verifies. auto (default): confirm after "
                             "about 1.5 s, so the phone has time to show its code; ask: print the code and read y or n "
                             "from stdin; refuse: cancel every pairing (for tests)")
    parser.add_argument('--pair-confirm-timeout', type=float, default=PAIR_CONFIRM_SECONDS, metavar='SECONDS',
                        help='X-1: no answer for this long refuses the pairing (default 120; shorter only for tests)')
    parser.add_argument('--pair-confirm-delay', type=float, default=PAIR_CONFIRM_AUTO_SECONDS, metavar='SECONDS',
                        help='with --pair-confirm auto: how long before the mock confirms (default 1.5; shorter only '
                             'for tests)')
    parser.add_argument('--folders-root', metavar='DIR',
                        help="v0.5: list this folder as the home folder for remote.folders (a test tree), instead of "
                             "this Mac's real home folder")
    parser.add_argument('--quiet', action='store_true', help='no log lines on stderr')
    args = parser.parse_args(argv)
    try:
        asyncio.run(serve(args))
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
