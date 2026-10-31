import Foundation
import PebbleProtocol

/// Lane S: what the demo's Pebble keeps for the Settings controls that were "On your Mac" rows, shaped as Pebble sends
/// it (read-only Pebble checkout: memory_learning.py's candidates, extensions.py, data_mirror.py, telemetry.py,
/// companion_tools.py, notifications.py). DemoClient owns one (`settingsDemo`) and answers through
/// `DemoClient+Settings`; refusals are Pebble's own words.
struct DemoSettings: Sendable {
    // MARK: Settings › Memory: learning candidates

    struct Candidate: Sendable, Hashable {
        var id: String
        var kind: String
        var status: String
        var reason: String?
        var content: String
        var scope: String
        var chatID: String
        /// How long ago Pebble's learning last looked at it.
        var ago: TimeInterval

        func json(now: Date) -> JSONValue {
            let updated = JSONValue.double(now.timeIntervalSince1970 - ago)
            return [
                "id": .string(id), "run_id": .string("run-" + id), "chat_id": .string(chatID), "kind": .string(kind),
                "scope": .string(scope), "slot": .string(kind), "content": .string(content), "fingerprint": "f0",
                "evidence": "{}", "input_id": .null, "expires": .null, "supersedes": .null, "status": .string(status),
                "reason": reason.map(JSONValue.string) ?? .null, "memory_id": .null, "created": updated,
                "updated": updated, "validated_proof": .null,
            ]
        }
    }

    static let web = "/Users/you/Projects/pebble-web"

    /// One proposal that disagrees with a saved preference, one test recipe waiting for its run to finish, and one
    /// quote Pebble didn't save: each state Pebble's Memory settings show.
    var candidates: [Candidate] = [
        Candidate(
            id: "cand-24h", kind: "profile", status: "conflict", reason: "active_value_differs",
            content: "Use 24-hour times in summaries.", scope: "global", chatID: DemoData.weatherChat, ago: 20 * 60),
        Candidate(
            id: "cand-lint", kind: "procedural", status: "pending", reason: "wait_for_settled_test_evidence",
            content: "", scope: web, chatID: DemoData.loginChat, ago: 4 * 60),
        Candidate(
            id: "cand-quota", kind: "semantic", status: "unsupported", reason: "quote_not_observed",
            content: "The API allows 600 requests a minute.", scope: web, chatID: DemoData.readmeChat, ago: 3 * 3600),
        // Pebble saved this one already: memory_candidates lists it, Pebble's settings don't.
        Candidate(
            id: "cand-saved", kind: "profile", status: "promoted", reason: nil,
            content: "Prefers short replies with the exact commands to run.", scope: "global",
            chatID: DemoData.readmeChat, ago: 5 * 86400),
    ]
    /// Memories the person added on the phone, for their ids.
    var added = 0

    func candidatesJSON(now: Date) -> JSONValue {
        .array(candidates.sorted { $0.ago < $1.ago }.map { $0.json(now: now) })
    }

    // MARK: Settings › Skills & connectors

    struct Extension: Sendable, Hashable {
        var id: String
        var kind: String
        var name: String
        var enabled: Bool
        var content: String
        var config: JSONValue
        /// Days ago it was added (the list is oldest first).
        var age: Double

        func json(now: Date) -> JSONValue {
            let capabilities: JSONValue =
                switch kind {
                case "plugin": config["tools"] ?? []
                case "skill": ["task guidance"]
                default: ["deny / request review"]
                }
            return [
                "id": .string(id), "kind": .string(kind), "name": .string(name), "content": .string(content),
                "config": config, "enabled": .bool(enabled), "capabilities": capabilities,
                "created": .double(now.timeIntervalSince1970 - age * 86_400),
            ]
        }
    }

    static let skillSnapshot = "5b1f0c9e2d7a4b8c6e3f1a0d9c8b7a6e5f4d3c2b1a0f9e8d7c6b5a4f3e2d1c0b"

    /// A skill with reference files (one long enough for a second page), a connector with an access grant that is still
    /// off, and a hook that is on.
    var extensions: [Extension] = [
        Extension(
            id: "ext-release", kind: "skill", name: "Release checklist", enabled: true,
            content:
                "---\nname: Release checklist\ndescription: Cut a release the way this team does.\n---\n\n1. Read references/steps.md.\n2. Run the tests and the linter.\n3. Add what changed to CHANGELOG.md.\n4. Tag the release only after the person approves.\n",
            config: [
                "bundle_digest": .string(skillSnapshot), "main": "SKILL.md",
                "files": [
                    ["path": "SKILL.md", "bytes": 212, "sha256": "a3f19c04b7e2"],
                    ["path": "references/steps.md", "bytes": .int(releaseSteps.utf8.count), "sha256": "7c2e90d1f45a"],
                    ["path": "scripts/bump_version.py", "bytes": 356, "sha256": "e41b6a0c9d27"],
                    ["path": "assets/badge.png", "bytes": 2_048, "sha256": "19d7f3a8c0b6"],
                ],
            ], age: 9),
        Extension(
            id: "ext-github", kind: "plugin", name: "GitHub", enabled: false,
            content: #"{"url": "https://api.githubcopilot.com/mcp/", "tools": ["search_issues", "get_issue"]}"#,
            config: [
                "transport": "http", "protocol_era": "2025-11-25", "url": "https://api.githubcopilot.com/mcp/",
                "tools": ["search_issues", "get_issue"], "catalogue_digest": "4f9c2a7d1e08", "protocol": "2025-06-18",
                "schemas": [
                    [
                        "name": "search_issues", "description": "Search issues in a repository.",
                        "inputSchema": [
                            "type": "object", "properties": ["query": ["type": "string"]], "required": ["query"],
                        ],
                    ],
                    [
                        "name": "get_issue", "description": "Read one issue.",
                        "inputSchema": [
                            "type": "object", "properties": ["number": ["type": "integer"]], "required": ["number"],
                        ],
                    ],
                ],
                "auth_binding": ["grant_id": "grant-1", "revision": 1, "digest": "b8e1d2"],
            ], age: 4),
        Extension(
            id: "ext-push", kind: "hook", name: "Ask before force pushes", enabled: true,
            content: "deny when a command runs git push --force\nrequest review when a command deletes a branch\n",
            config: [:], age: 2),
    ]

    /// The text of the skill's reference files (Pebble keeps them in the snapshot).
    static let skillFiles: [String: String] = [
        "references/steps.md": releaseSteps,
        "scripts/bump_version.py":
            "import re, sys\n\n# Bumps the version in package.json; the person reviews the change.\npath = sys.argv[1]\ntext = open(path).read()\nmajor, minor, patch = map(int, re.search(r'\"version\": \"(\\d+)\\.(\\d+)\\.(\\d+)', text).groups())\nprint(f'{major}.{minor}.{patch + 1}')\n",
    ]

    /// About 4,000 characters: Pebble's 3,000-character pages make it two.
    static let releaseSteps = """
        # Release steps

        These are the steps this team follows for every release of pebble-web. Follow them in order, and stop to ask \
        the person whenever a step says so. Nothing here is approved in advance: each command still asks as Pebble's \
        permissions say.

        ## Before you start

        1. Check that main is green. The last run of the tests and the linter must have passed on the commit you \
        release. If either failed, stop and tell the person which one and why.
        2. Make sure the working tree is clean. Uncommitted changes are never part of a release; ask the person what \
        to do with them.
        3. Read the commits since the last tag. Group them as Added, Changed and Fixed, and leave out commits that \
        only touch tests or formatting.

        ## The changelog

        4. Write the CHANGELOG.md entry in the team's words. Newest first, with today's date and the new version \
        number. Each line says what changed for the people who use the site, not how the code changed.
        5. Keep the entry short: at most twelve lines. Link an issue only when the commit names one.
        6. Show the person the entry before you save it, and use their wording when they change it.

        ## The version

        7. Run scripts/bump_version.py on package.json. It prints the next patch version; it changes nothing by itself.
        8. A release that adds something uses the next minor version instead, and one that removes or renames \
        something the next major version. Ask the person when you are not sure which it is.
        9. Update the version in package.json and in the footer of the site, and nowhere else.

        ## The tag

        10. Ask the person to approve the tag. Never tag on your own, even when every check passed.
        11. Tag the release commit as vX.Y.Z, matching package.json exactly.
        12. Push the tag only after the person says so. A pushed tag cannot be taken back quietly.

        ## After the release

        13. Open the release page and paste the notes from the changelog entry.
        14. Check that the site's footer shows the new version once the deploy finishes.
        15. Tell the person what was released, with the tag and a link to the release page.
        16. If anything failed after the tag, say so plainly and suggest a fix release; never move the tag.

        ## The release notes

        17. Start the notes with one sentence that says what this release is for, in plain words.
        18. Then list the changes under Added, Changed and Fixed, as in the changelog, with the same wording.
        19. Name the people who reported a fixed problem when their issue names them, and thank them once.
        20. End with how to update: for the site nothing is needed; for the command-line tool, the install command.
        21. Keep the notes under 200 words. Longer notes go to the blog, which the person writes themselves.

        ## If something goes wrong

        22. When the deploy fails, read its log and tell the person the first error, word for word, before you change \
        anything.
        23. When a test fails only on the release commit, compare it with the last green commit and say what differs.
        24. When the person asks to undo a release, propose a fix release with the change reverted; deleting a pushed \
        tag breaks everyone who already fetched it.
        25. Keep a short note of what happened in the conversation, so the next release can avoid it.

        ## Things to avoid

        - Never edit the changelog entries of earlier releases.
        - Never release on a Friday afternoon without asking first.
        - Never include secrets, tokens or local paths in release notes.
        - Never skip the tests because a change looks small.
        """

    // MARK: Settings › Data & storage

    /// What Pebble noticed in the person's Documents copies, oldest first (data_mirror.py keeps the last dozen), with
    /// how long ago.
    var storageEvents: [(text: String, ago: TimeInterval)] = [
        ("Copies in Documents are on.", 6 * 86_400),
        ("Forgot 1 memory deleted from the Memory folder.", 2 * 86_400),
        ("Kept the memories deleted from \"Facts & knowledge.md\"; their entries come back in the file.", 26 * 3600),
    ]
    /// A memory entry deleted from its file in Documents a moment ago: Pebble acts once it has lasted a minute, or at
    /// once when the person chooses Update copies now.
    var waitingDeletions = 1

    /// The parts of `storage_summary` lane S reads: the changes and the deletions that wait.
    func storageParts(now: Date) -> [String: JSONValue] {
        [
            "events": .array(storageEvents.map { event in
                ["at": .double(now.timeIntervalSince1970 - event.ago), "kind": "storage", "text": .string(event.text)]
            }),
            "documents": [
                "enabled": true, "path": "/Users/you/Documents/Pebble",
                "pending": ["trash": 0, "forget": 0, "waiting": ["conversations": 0, "memory": .int(waitingDeletions)]],
            ],
        ]
    }

    /// The Documents copy pass (`storage_refresh`): the waiting deletion is old enough now, so Pebble forgets it.
    mutating func refreshCopies() {
        guard waitingDeletions > 0 else { return }
        let memories = "memor" + (waitingDeletions == 1 ? "y" : "ies")
        storageEvents.append(("Forgot \(waitingDeletions) \(memories) deleted from the Memory folder.", 0))
        waitingDeletions = 0
        if storageEvents.count > 12 { storageEvents.removeFirst(storageEvents.count - 12) }
    }

    mutating func note(_ text: String) {
        storageEvents.append((text, 0))
        if storageEvents.count > 12 { storageEvents.removeFirst(storageEvents.count - 12) }
    }

    // MARK: Settings › Privacy & Stealth: usage telemetry

    /// Off, as Pebble starts; on since then once the person turns it on.
    var telemetrySince: Date?

    static let consentVersion = "pebble.telemetry.consent/1"
    /// telemetry.py `CONSENT_TEXT`, word for word.
    static let consentText =
        "Pebble can keep a private usage log on this Mac to help measure its reliability. It records only counts and rounded values: how each task ended, how many steps it took, which built-in tools it used and how often, approvals and questions, and rounded durations, token counts and memory or CPU use. It never records your messages, the model's replies, files, memory notes, web addresses, account details or credentials. Nothing is sent anywhere: you can save the log to a file you choose and share it yourself. At most 1,000 events or 256 KB are kept, for 30 days. Turning this off deletes the log."

    /// `telemetry_get` and `telemetry_set`'s answer (telemetry.py `_status`).
    func telemetryJSON() -> JSONValue {
        let on = telemetrySince != nil
        return [
            "schema": "pebble.telemetry/1", "enabled": .bool(on), "consent_version": on ? .string(Self.consentVersion) : .null,
            "consented_at": telemetrySince.map { .int(Int($0.timeIntervalSince1970)) } ?? .null,
            "current_consent_version": .string(Self.consentVersion), "consent_text": .string(Self.consentText),
            "install_id": on ? "7d41c0e9a2b84f6e9c13a5d07b2e8f40" : .null, "events": 0, "bytes": 0,
            "dropped": 0, "expired": 0, "refused": 0,
            "fields": [
                "run_settled": [
                    "approvals", "input_tokens_log2", "model_ms_log2", "output_tokens_log2", "questions", "rejections",
                    "state", "steps", "tools", "uncertain", "wall_ms_log2",
                ],
                "resource_sample": ["cpu_percent_bucket", "footprint_mb_log2"], "error": ["code"],
            ],
            "limits": ["max_events": 1000, "max_bytes": 262_144, "retention_days": 30], "destination": .null,
            "network_upload": false, "export": "native_save_dialog",
        ]
    }

    // MARK: Settings › Permissions: Pebble's Shell

    /// Saved ("always") and this-session grants, as companion_tools.py `grants` merges them.
    var shellGrants: [String: [String: String]] = [
        "hosts": ["registry.npmjs.org": "always", "api.github.com": "session"],
        "folders": ["/Users/you/Projects/pebble-web/dist": "always"],
    ]

    func shellGrantsJSON() -> JSONValue {
        .object(shellGrants.mapValues { grants in .object(grants.mapValues(JSONValue.string)) })
    }

    // MARK: Settings › General: notification delivery

    /// Schedules whose banners the person muted (notifications.py keeps their ids).
    var mutedJobs: Set<String> = []
}
