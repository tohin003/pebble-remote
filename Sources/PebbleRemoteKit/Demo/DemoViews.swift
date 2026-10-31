import Foundation
import PebbleProtocol

// Lane G (2026-10-31): Pebble's views in the demo (contract 3.12, pebble-ui-spec v1), so the UI audit and the person
// see every kind: the native views (form, table, chart, plan, evidence, quiz, diagram, dashboard, prototype, html and
// one kind this version doesn't draw) as artifact rows (artifacts._public with artifact_inputs.decorate), and the work
// view's cards on the activity items, shaped like Pebble's own builders make them (the spec's fixtures.json).

struct DemoViews: Sendable {
    /// Each conversation's views, oldest first, as artifact rows.
    private(set) var rows: [String: [JSONValue]]
    /// Each run's plan as the last `plan` event sent it (run_plans' steps).
    var plans: [String: JSONValue] = [:]
    private var counter = 0

    init(now: Date) {
        rows = Self.seed(now: now)
    }

    func list(in chat: String) -> [JSONValue] { rows[chat] ?? [] }

    func row(_ id: String, in chat: String) -> JSONValue? { rows[chat]?.first { $0["id"]?.string == id } }

    /// Replaces a view's row (an answer, a stop) or adds a new one.
    mutating func put(_ row: JSONValue, in chat: String) {
        guard let id = row["id"]?.string else { return }
        var list = rows[chat] ?? []
        if let index = list.firstIndex(where: { $0["id"]?.string == id }) { list[index] = row } else { list.append(row) }
        rows[chat] = list
    }

    mutating func forget(chat: String) { rows[chat] = nil }

    mutating func nextID() -> String {
        counter += 1
        return "v-demo-\(counter)"
    }

    // MARK: - Rows

    static func row(
        _ id: String, chat: String, run: String?, title: String, kind: String, data: JSONValue, at: Date,
        status: String = "ready", revision: Int = 1, extra: [String: JSONValue] = [:]
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id), "chat_id": .string(chat), "revision": .int(revision), "title": .string(title),
            "kind": .string(kind), "data": data, "owner_run_id": run.map(JSONValue.string) ?? .null,
            "status": .string(status), "created": .double(at.timeIntervalSince1970),
            "updated": .double(at.timeIntervalSince1970), "evidence_ids": [],
        ]
        for (key, value) in extra { object[key] = value }
        return .object(object)
    }

    /// A form's question as artifact_inputs.decorate attaches it (interaction.question's row).
    static func formQuestion(
        _ id: String, run: String, chat: String, fields: [JSONValue], status: String, answer: JSONValue, at: Date
    ) -> JSONValue {
        let items: [JSONValue] = fields.map { field in
            ["id": field["id"] ?? .null, "title": field["label"] ?? .null, "options": field["options"] ?? []]
        }
        return [
            "id": .string(id), "run_id": .string(run), "call_id": "3:ui", "revision": 1, "required": true,
            "status": .string(status), "items": .array(items), "answer": answer, "created": .double(at.timeIntervalSince1970),
            "chat_id": .string(chat),
        ]
    }

    /// The question items a form asks (artifact_inputs.publish: each field's id, label and options).
    static func questionItems(_ fields: [JSONValue]) -> JSONValue {
        .array(
            fields.map { field in
                [
                    "id": field["id"] ?? .null, "title": field["label"] ?? .null, "options": field["options"] ?? [],
                    "allow_free_text": .bool(field["type"]?.string == "text"),
                ]
            })
    }

    // MARK: - The deploy form: Pebble asks before it picks a port

    static let portFields: [JSONValue] = [
        [
            "id": "port", "label": "Which port should the preview use?", "type": "choice", "required": true,
            "options": [
                ["id": "p4174", "label": "4174, next to the busy one"], ["id": "p5173", "label": "5173, Vite's usual port"],
                ["id": "p8080", "label": "8080"],
            ],
        ],
        [
            "id": "share", "label": "Who should get the preview link?", "type": "text", "required": true,
            "placeholder": "Names or a team",
        ],
    ]

    static var portForm: JSONValue {
        [
            "description": "Port 4173 is taken by another program. Pebble won't stop it without asking.",
            "fields": .array(portFields), "submit_label": "Start the preview",
        ]
    }

    // MARK: - The seeded views

    static func seed(now: Date) -> [String: [JSONValue]] {
        func ago(_ seconds: Double) -> Date { now.addingTimeInterval(-seconds) }
        let commits = DemoData.commitsChat, commitsRun = "r-commits"
        let login = DemoData.loginChat, loginRun = DemoData.loginRun
        let deploy = DemoData.deployChat, deployRun = DemoData.deployRun
        let answeredPort: JSONValue = ["port": ["option_id": "p5173"], "share": ["text": "The web team"]]
        return [
            commits: [
                row(
                    "v-commits-table", chat: commits, run: commitsRun, title: "Commits by author", kind: "table",
                    data: [
                        "caption": "This week, from git shortlog",
                        "columns": [["id": "author", "label": "Author"], ["id": "commits", "label": "Commits"], ["id": "areas", "label": "Areas"]],
                        "rows": [
                            ["author": "Sam", "commits": 18, "areas": "settings, theme"],
                            ["author": "Ada", "commits": 14, "areas": "auth"],
                            ["author": "Lin", "commits": 7, "areas": "docs"],
                            ["author": "Ravi", "commits": 3, "areas": .null],
                        ],
                    ], at: ago(26 * 3600), revision: 2),  // lane T: its first revision had one author fewer
                row(
                    "v-commits-chart", chat: commits, run: commitsRun, title: "Commits per day", kind: "chart",
                    data: [
                        "type": "bar", "x_key": "day", "y_keys": ["commits"], "labels": ["commits": "Commits"],
                        "rows": [
                            ["day": "Mon", "commits": 9], ["day": "Tue", "commits": 12], ["day": "Wed", "commits": 6],
                            ["day": "Thu", "commits": 10], ["day": "Fri", "commits": 5],
                        ],
                        "caption": "Tuesday had the most: the settings work landed.",
                    ], at: ago(26 * 3600)),
                row(
                    "v-commits-dashboard", chat: commits, run: commitsRun, title: "This week in pebble-web", kind: "dashboard",
                    data: [
                        "columns": 2,
                        "panels": [
                            ["id": "total", "title": "Commits", "kind": "metric", "data": ["value": 42, "delta": 6, "unit": "commits", "caption": "6 more than last week"]],
                            ["id": "authors", "title": "Authors", "kind": "metric", "data": ["value": 4, "delta": 0]],
                            [
                                "id": "files", "title": "Busiest files", "kind": "table",
                                "data": [
                                    "columns": [["id": "file", "label": "File"], ["id": "changes", "label": "Changes"]],
                                    "rows": [["file": "src/settings/theme.ts", "changes": 11], ["file": "src/auth/session.ts", "changes": 8]],
                                ],
                            ],
                            ["id": "runs", "title": "Recent runs", "kind": "table", "binding": ["source": "runs.recent"]],
                        ],
                    ], at: ago(26 * 3600),
                    extra: [
                        "bindings": [
                            [
                                "panel_id": "runs", "source": "runs.recent", "as_of": .double(ago(26 * 3600).timeIntervalSince1970),
                                "digest": "sha256:9f2c41d07ab3",
                                "data": [
                                    "columns": [["id": "task", "label": "Task"], ["id": "state", "label": "State"]],
                                    "rows": [["task": "Summarize this week's commits", "state": "completed"], ["task": "Fix the login redirect loop", "state": "running"]],
                                ],
                            ]
                        ]
                    ]),
                row(
                    "v-commits-evidence", chat: commits, run: commitsRun, title: "Where the numbers came from", kind: "evidence",
                    data: [
                        "items": [
                            ["id": "shortlog", "label": "Commit counts", "evidence_id": "5:call_shortlog", "summary": "git shortlog -sn --since=\"1 week ago\": 42 commits by 4 authors"],
                            ["id": "changelog", "label": "Breaking changes", "evidence_id": "4:call_changelog", "summary": "CHANGELOG.md lists none since 1.9."],
                        ]
                    ], at: ago(26 * 3600)),
                // A kind this version doesn't draw: it shows its title and "Update the app to see this view".
                row(
                    "v-commits-timeline", chat: commits, run: commitsRun, title: "The week, day by day", kind: "timeline",
                    data: ["events": [["date": "2026-10-26", "title": "Settings work started"], ["date": "2026-10-28", "title": "Theme merged"]]],
                    at: ago(26 * 3600)),
            ],
            login: [
                row(
                    "v-login-diagram", chat: login, run: loginRun, title: "How a request reaches the app", kind: "diagram",
                    data: [
                        "nodes": [["id": "req", "label": "Request"], ["id": "mw", "label": "Auth middleware"], ["id": "app", "label": "App"], ["id": "login", "label": "Login page"]],
                        "edges": [
                            ["from": "req", "to": "mw", "label": "checks session"], ["from": "mw", "to": "app", "label": "passes on"],
                            ["from": "mw", "to": "login", "label": "no session"], ["from": "login", "to": "req", "label": "signs in again"],
                        ],
                    ], at: ago(60)),
                row(
                    "v-login-plan", chat: login, run: loginRun, title: "The fix, step by step", kind: "plan",
                    data: [
                        "steps": [
                            ["id": "read", "title": "Read the middleware", "status": "completed", "evidence_ids": ["1:call_read"]],
                            ["id": "find", "title": "Find where the redirect loops", "status": "in_progress", "evidence_ids": []],
                            ["id": "fix", "title": "Fix the session refresh", "status": "pending", "evidence_ids": []],
                        ]
                    ], at: ago(60)),
            ],
            deploy: [
                row(
                    "v-deploy-form", chat: deploy, run: deployRun, title: "Choose the preview's port", kind: "form",
                    data: portForm, at: ago(5 * 3600),
                    extra: [
                        "form_question": formQuestion(
                            "q-deploy-port", run: deployRun, chat: deploy, fields: portFields, status: "answered",
                            answer: answeredPort, at: ago(5 * 3600))
                    ]),
            ],
            DemoData.readmeChat: [
                row(
                    "v-readme-quiz", chat: DemoData.readmeChat, run: DemoData.readmeRun, title: "What's new in 2.0", kind: "quiz",
                    data: [
                        "duration_minutes": 5,
                        "questions": [
                            ["id": "q1", "question": "Which command starts the docs site?", "choices": ["npm run dev", "npm start", "make docs"]],
                            ["id": "q2", "question": "Where do settings live in 2.0?", "choices": ["settings.json", "A sidebar in the app", "Environment variables"]],
                        ],
                    ], at: ago(30 * 60)),
            ],
            DemoData.emailsChat: [
                row(
                    "v-emails-prototype", chat: DemoData.emailsChat, run: DemoData.emailsRun, title: "Onboarding screens", kind: "prototype",
                    data: [
                        "start": "welcome", "viewport": "phone",
                        "screens": [
                            [
                                "id": "welcome", "title": "Welcome",
                                "components": [
                                    ["type": "heading", "text": "Welcome to Pebble"],
                                    ["type": "card", "title": "Day 1", "body": "A short hello and one thing to try."],
                                    ["type": "image_placeholder", "label": "Hero picture", "aspect": "16:9"],
                                    ["type": "button", "label": "Continue", "goto": "prefs"],
                                ],
                            ],
                            [
                                "id": "prefs", "title": "Your emails",
                                "components": [
                                    ["type": "toggle", "label": "Weekly tips"],
                                    ["type": "input", "label": "First name", "placeholder": "Sam"],
                                    ["type": "list", "items": ["Day 1: welcome", "Day 3: first task", "Day 7: tips"]],
                                    ["type": "nav", "items": [["label": "Welcome", "goto": "welcome"], ["label": "Emails", "goto": "prefs"]]],
                                ],
                            ],
                        ],
                    ], at: ago(25 * 60)),
            ],
            "c-weather": [
                row(
                    "v-weather-chart", chat: "c-weather", run: "r-weather", title: "Lisbon this weekend", kind: "chart",
                    data: [
                        "type": "line", "x_key": "day", "y_keys": ["high", "low"], "labels": ["high": "High (°C)", "low": "Low (°C)"],
                        "rows": [["day": "Fri", "high": 22, "low": 15], ["day": "Sat", "high": 24, "low": 16], ["day": "Sun", "high": 21, "low": 14]],
                    ], at: ago(3 * 86400)),
            ],
            "c-site": [
                // html is drawn only on the Mac (x-pebble-surfaces): the phone says so.
                row(
                    "v-site-html", chat: "c-site", run: "r-site", title: "Docs home page preview", kind: "html",
                    data: ["html": "<h1>Pebble docs</h1>"], at: ago(10 * 60), status: "review"),
            ],
        ]
    }
}

// MARK: - The work view on the demo's activity items

extension DemoViews {
    /// Views for the seeded runs' items, by run and seq (run_activity items; DemoData.activity's seqs are n × 64).
    static let seeded: [String: [Int: JSONValue]] = [
        "r-commits": [
            192: ["v": 1, "type": "search", "tool": "Grep", "query": "BREAKING", "hits": 0],
            256: ["v": 1, "type": "read", "path": "CHANGELOG.md", "start": 1, "total": 412],
            384: ["v": 1, "type": "read", "path": "src/settings/theme.ts", "start": 1, "total": 96],
            320: [
                "v": 1, "type": "command", "command": "git shortlog -sn --since=\"1 week ago\"", "where": "Project folder",
                "network": false, "state": "done", "exit": 0, "seconds": 1.8,
                "tail": ["    18\tSam", "    14\tAda", "     7\tLin", "     3\tRavi"],
            ],
            448: [
                "v": 1, "type": "checks", "verdict": "Verified · the counts match git shortlog",
                "requirements": [["text": "Count every commit since last Monday", "state": "met"]], "issues": 0,
            ],
        ],
        DemoData.deployRun: [
            // A view type this version doesn't know: the step shows its words and "Update the app to see this view".
            64: ["v": 1, "type": "preview_frame", "frames": 3],
            128: [
                "v": 1, "type": "command", "command": "npm run preview", "where": "Project folder", "network": false,
                "state": "failed", "exit": 1, "seconds": 12.4,
                "tail": ["> pebble-web@2.0.0 preview", "> vite preview --strictPort", "Error: Port 4173 is already in use"],
            ],
        ],
        DemoData.themeRun: [
            64: ["v": 1, "type": "read", "path": "src/settings/Settings.tsx", "start": 1, "total": 188],
            128: ["v": 1, "type": "edit", "path": "src/settings/ThemeToggle.tsx", "added": 18, "removed": 4, "state": "done"],
            192: [
                "v": 1, "type": "checks", "verdict": "A check asked for more evidence", "issues": 1, "unmet": 1,
                "repairable": true, "requirements": [["text": "A test covers the dark mode toggle", "state": "open"]],
            ],
        ],
        DemoData.mailRun: [
            192: [
                "v": 1, "type": "window", "app": "Mail", "title": "Weekly update", "verb": "Pressed", "target": "Send",
                "verdict": "uncertain", "picture": ["ref": "demo-mail-1", "width": 640, "height": 420],
                "point": ["x": 590, "y": 36],
            ],
        ],
        DemoData.readmeRun: [
            192: ["v": 1, "type": "review", "action": "command", "state": "waiting"],
            256: ["v": 1, "type": "agent", "name": "Link checker", "state": "running", "depth": 1, "parent": "root"],
            320: ["v": 1, "type": "agent", "name": "Proofreader", "state": "done", "depth": 1, "parent": "root", "seconds": 12.9, "tokens": 4100],
        ],
        "r-weather": [
            64: ["v": 1, "type": "web", "query": "Lisbon weather this weekend", "sites": ["ipma.pt", "weather.com"]],
        ],
    ]

    /// The seeded runs' items with their views.
    static func decorated(_ seededItems: [String: [JSONValue]]) -> [String: [JSONValue]] {
        var items = seededItems
        for (run, views) in seeded {
            guard var list = items[run] else { continue }
            for index in list.indices {
                guard let seq = list[index]["seq"]?.int, let view = views[seq], case .object(var item) = list[index] else {
                    continue
                }
                item["view"] = view
                list[index] = .object(item)
            }
            items[run] = list
        }
        return items
    }

    /// The login run's steps, as the demo plays them: read, search, read, edit, tests.
    static let loginViews: [JSONValue] = [
        ["v": 1, "type": "read", "path": "src/auth/session.ts", "start": 1, "total": 212],
        ["v": 1, "type": "search", "tool": "Grep", "query": "redirect", "hits": 7],
        ["v": 1, "type": "read", "path": "src/routes/login.tsx", "start": 1, "total": 96],
        ["v": 1, "type": "edit", "path": "src/auth/session.ts", "added": 4, "removed": 2, "state": "done", "action_id": "act_login_edit"],
        [
            "v": 1, "type": "tests", "recipe": "npm-test", "state": "done", "passed": 42, "failed": 0, "skipped": 0,
            "errors": 0, "total": 42, "exit": 0, "seconds": 2.2,
        ],
    ]

    /// The login run's plan as UpdatePlan would send it, after `done` steps.
    static func loginPlan(done: Int) -> JSONValue {
        let titles = ["Read the session code", "Find the redirect loop", "Fix the session check", "Run the tests"]
        return .array(
            titles.enumerated().map { index, title -> JSONValue in
                let status = index < done ? "completed" : index == done ? "in_progress" : "pending"
                return ["title": .string(title), "status": .string(status)]
            })
    }

    /// A view while its step runs: the same view, its state "running" when it carries one.
    static func running(_ view: JSONValue) -> JSONValue {
        guard case .object(var object) = view, object["state"] != nil else { return view }
        object["state"] = "running"
        return .object(object)
    }

    /// run_activity's header and summary for a demo run (work_view.header and work_view.summary): the summary only once
    /// the run settled, counted from its items' views as Pebble does.
    static func receipt(items: [JSONValue], state: String, elapsed: Double, plan: JSONValue?) -> (header: JSONValue, summary: JSONValue) {
        var header: [String: JSONValue] = ["plan": .null, "state": .string(state), "elapsed": .double(elapsed)]
        if let plan, let steps = plan.array {
            let done = steps.filter { $0["status"]?.string == "completed" }.count
            header["plan"] = ["done": .int(done), "total": .int(steps.count), "steps": plan]
        }
        let live: Set<String> = ["queued", "running", "retry_wait", "waiting_approval", "waiting_input"]
        guard !live.contains(state) else { return (.object(header), .null) }
        var files: [String: (Int, Int)] = [:]
        var commands = 0, failed = 0
        var tests: JSONValue = .null, checks: JSONValue = .null
        for item in items {
            guard let view = item["view"], let type = view["type"]?.string else { continue }
            let state = view["state"]?.string
            switch type {
            case "edit" where state == "done":
                let key = view["path"]?.string ?? "private:\(item["seq"]?.int ?? 0)"
                let old = files[key] ?? (0, 0)
                files[key] = (old.0 + (view["added"]?.int ?? 0), old.1 + (view["removed"]?.int ?? 0))
            case "command" where ["done", "failed", "stopped"].contains(state ?? ""):
                commands += 1
                if state != "done" { failed += 1 }
            case "tests" where ["done", "failed"].contains(state ?? ""):
                tests = ["passed": .int(view["passed"]?.int ?? 0), "failed": .int(view["failed"]?.int ?? 0)]
            case "checks":
                checks = view["verdict"] ?? .null
            default:
                break
            }
        }
        let added = files.values.reduce(0) { $0 + $1.0 }
        let removed = files.values.reduce(0) { $0 + $1.1 }
        var fileCounts: JSONValue = .null
        if !files.isEmpty { fileCounts = ["count": .int(files.count), "added": .int(added), "removed": .int(removed)] }
        var commandCounts: JSONValue = .null
        if commands > 0 { commandCounts = ["count": .int(commands), "failed": .int(failed)] }
        let tokens: JSONValue = ["input": 18_240, "cached": 12_100, "output": 1_460]
        let summary: JSONValue = [
            "files": fileCounts, "commands": commandCounts, "tests": tests, "checks": checks,
            "seconds": .double((elapsed * 10).rounded() / 10), "tokens": tokens,
        ]
        return (.object(header), summary)
    }
}
