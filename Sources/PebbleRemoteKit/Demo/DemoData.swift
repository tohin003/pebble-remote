import Foundation
import PebbleProtocol

// The demo's simulated Pebble: conversations, runs, cards and a question, in the shapes real Pebble sends (state(),
// chat(), the actions table, interaction.question()). Content is invented and neutral: no real paths or people.

struct DemoMessage: Sendable, Hashable {
    var id: String
    var role: String
    var content: String
    var created: Date
    var runID: String?
    /// Photos and files sent with this message (attach_bytes chips, bound to it).
    var attachments: [JSONValue] = []

    var json: JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id), "role": .string(role), "content": .string(content),
            "created": .double(created.timeIntervalSince1970), "attachments": .array(attachments),
        ]
        if role == "assistant", let runID { object["run_id"] = .string(runID) }
        return .object(object)
    }
}

struct DemoAction: Sendable, Hashable {
    var id: String
    var chatID: String
    var kind: String
    var status: String
    var payload: JSONValue
    var created: Date

    var json: JSONValue {
        [
            "id": .string(id), "chat_id": .string(chatID), "kind": .string(kind), "status": .string(status),
            "payload": payload, "created": .double(created.timeIntervalSince1970),
        ]
    }
}

struct DemoQuestion: Sendable, Hashable {
    var id: String
    var runID: String
    var chatID: String
    var revision: Int
    var required: Bool
    var status: String
    var items: JSONValue
    var created: Date
    var answer: JSONValue = .null

    var json: JSONValue {
        [
            "id": .string(id), "run_id": .string(runID), "call_id": "1:ask", "revision": .int(revision),
            "required": .bool(required), "status": .string(status), "items": items, "answer": answer,
            "created": .double(created.timeIntervalSince1970), "answered": .null, "chat_id": .string(chatID),
        ]
    }
}

struct DemoRun: Sendable, Hashable {
    var id: String
    var chatID: String
    var state: String
    var steps: Int
    var elapsed: Double
    var error: String?
    var created: Date
    var updated: Date
    /// The reply message this run writes.
    var messageID: String

    var json: JSONValue {
        [
            "id": .string(id), "chat_id": .string(chatID), "state": .string(state), "steps": .int(steps),
            "elapsed": .double(elapsed), "error": error.map(JSONValue.string) ?? .null,
            "created": .double(created.timeIntervalSince1970), "updated": .double(updated.timeIntervalSince1970),
        ]
    }

    var isLive: Bool { ["queued", "running", "retry_wait"].contains(state) }
}

struct DemoChat: Sendable, Hashable {
    var id: String
    var title: String
    var workspace: String?
    var updated: Date
    var messages: [DemoMessage] = []
    var actions: [DemoAction] = []
    var questions: [DemoQuestion] = []

    var rowJSON: JSONValue {
        [
            "id": .string(id), "title": .string(title), "workspace": workspace.map(JSONValue.string) ?? .null,
            "updated": .double(updated.timeIntervalSince1970),
        ]
    }
}

enum DemoData {
    static let version = "1.9.28"
    static let macName = "MacBook Pro"

    static let permissions: JSONValue = [
        "mode": "auto",
        "tools": [
            "files": true, "edits": true, "tests": true, "apps": true, "web": true, "terminal": true, "plugins": true,
            "views": true, "screen": false, "capture": true,
        ],
    ]

    static let model: JSONValue = [
        "state": "ready", "configured": true, "name": "gpt-5.1", "path": "", "context": 272_000, "kind": "chatgpt",
        "provider": "ChatGPT", "profile_id": "chatgpt", "budget": 272_000, "protocol": "responses",
        "efforts": ["low", "medium", "high"], "effort": "medium", "default_effort": "medium", "local": false,
    ]

    // Ids of the scripted conversations and runs.
    static let loginChat = "c-login"
    static let loginRun = "r-login"
    static let readmeChat = "c-readme"
    static let readmeRun = "r-readme"
    static let readmeCard = "a-npm-test"
    static let emailsChat = "c-emails"
    static let emailsRun = "r-emails"
    static let emailsQuestion = "q-tone"
    static let commitsChat = "c-commits"
    static let deployChat = "c-deploy"
    static let deployRun = "r-deploy"
    static let weatherChat = "c-weather"
    // Finishing and recovering a task (lane R): a held task, an uncertain step, a running command.
    static let themeChat = "c-theme"
    static let themeRun = "r-theme"
    static let themeEdit = "a-theme-edit"
    static let mailChat = "c-mail"
    static let mailRun = "r-mail"
    static let mailWindow = "session-mail"
    static let siteChat = "c-site"
    static let siteRun = "r-site"
    static let siteServer = "proc-dev"
    static let siteSync = "proc-sync"
    /// The conversations the demo opens with.
    static let seededChats = 9

    /// The login fix's reply, streamed token by token.
    static let loginReply = """
        The loop came from the session cookie. It was set with `SameSite=Strict`, so Safari dropped it on the way back \
        from the sign-in page, and the app sent you to /login again.

        I changed it to `SameSite=Lax` in `src/auth/session.ts` and added a test for the redirect. All 42 tests pass.
        """

    static let readmeAfterApproval = "\n\nThe docs tests pass (42 of 42). The README is ready for 2.0."
    static let themeAfterTests = "\n\nThe tests pass (18 of 18), including a new one for the toggle. The change is verified."
    static let themeAfterFinish =
        "\n\nI ran the tests to finish: 18 of 18 pass, including a new one for the toggle. The change is verified."
    /// The new run's reply after a model handoff, in its new conversation.
    static let handoffReply = """
        Continuing on the new model. I read the conversation above: the preview didn't start because port 4173 was \
        already in use. This is the demo, so there's no Mac behind me; with your Mac paired, I'd start the preview on \
        another port now.
        """
    static let readmeAfterRejection =
        "\n\nOkay, I won't run the tests. The README changes are in place; run `npm test` yourself when you're ready."

    static func emailsReply(tone: String) -> String {
        """
        Here's the sequence, in a \(tone.lowercased()) tone:

        1. **Welcome** (day 0): what Pebble does, and one task to try first.
        2. **Your first task** (day 2): how reviews work, and how to approve from your phone.
        3. **Tips** (day 7): Fast replies, Stealth Lockdown and the Toolbox.

        Want me to write the full text of each?
        """
    }

    static func seed(now: Date) -> (chats: [DemoChat], runs: [DemoRun]) {
        func ago(_ seconds: Double) -> Date { now.addingTimeInterval(-seconds) }
        var chats: [DemoChat] = []
        var runs: [DemoRun] = []

        // 1. Working now: the reply streams in once the demo connects.
        var login = DemoChat(
            id: loginChat, title: "Fix the login redirect loop", workspace: "/Users/you/Projects/pebble-web", updated: ago(40))
        login.messages = [
            DemoMessage(
                id: "m-login-1", role: "user",
                content: "Signing in on Safari sends me back to /login forever. Can you find out why and fix it?",
                created: ago(42))
        ]
        runs.append(
            DemoRun(
                id: loginRun, chatID: loginChat, state: "running", steps: 1, elapsed: 2, error: nil, created: ago(41),
                updated: ago(40), messageID: "m-login-reply"))
        chats.append(login)

        // 2. Waiting for approval: npm test.
        var readme = DemoChat(
            id: readmeChat, title: "Update the README for 2.0", workspace: "/Users/you/Projects/pebble-docs",
            updated: ago(6 * 60))
        readme.messages = [
            DemoMessage(
                id: "m-readme-1", role: "user",
                content: "Update the README for 2.0 and check that the docs tests still pass.", created: ago(9 * 60)),
            DemoMessage(
                id: "m-readme-reply", role: "assistant",
                content: "I've updated the README: new install steps, the 2.0 feature list and a shorter quick start.\n\nBefore I finish, I'd like to run the docs tests.",
                created: ago(6 * 60), runID: readmeRun),
        ]
        readme.actions = [
            DemoAction(
                id: readmeCard, chatID: readmeChat, kind: "command", status: "pending",
                payload: [
                    "command": "npm test", "root": "/Users/you/Projects/pebble-docs", "risk": "Project script",
                    "network": false, "writable": false,
                    "guard_review": "The docs tests read fixtures outside the project, so Pebble asks first.",
                ], created: ago(6 * 60))
        ]
        runs.append(
            DemoRun(
                id: readmeRun, chatID: readmeChat, state: "waiting_approval", steps: 7, elapsed: 51, error: nil,
                created: ago(9 * 60), updated: ago(6 * 60), messageID: "m-readme-reply"))
        chats.append(readme)

        // 3. Waiting for an answer: a question with options.
        var emails = DemoChat(
            id: emailsChat, title: "Plan the onboarding emails", workspace: "/Users/you/Projects/pebble-site",
            updated: ago(25 * 60))
        emails.messages = [
            DemoMessage(
                id: "m-emails-1", role: "user", content: "Draft a three-email onboarding sequence for new Pebble users.",
                created: ago(26 * 60)),
            DemoMessage(
                id: "m-emails-reply", role: "assistant",
                content: "I'll draft three emails: a welcome, a first task, and tips after a week. One question first.",
                created: ago(25 * 60), runID: emailsRun),
        ]
        emails.questions = [
            DemoQuestion(
                id: emailsQuestion, runID: emailsRun, chatID: emailsChat, revision: 1, required: true, status: "pending",
                items: [
                    [
                        "id": "tone", "title": "Which tone should the welcome emails use?",
                        "options": [
                            ["id": "warm", "label": "Warm and friendly", "description": "First names, a little playful"],
                            ["id": "brief", "label": "Short and direct", "description": "Three sentences at most"],
                            ["id": "formal", "label": "Formal", "description": ""],
                        ],
                        "allow_free_text": true,
                    ]
                ], created: ago(25 * 60))
        ]
        runs.append(
            DemoRun(
                id: emailsRun, chatID: emailsChat, state: "waiting_input", steps: 2, elapsed: 9, error: nil,
                created: ago(26 * 60), updated: ago(25 * 60), messageID: "m-emails-reply"))
        chats.append(emails)

        // 4. Finished.
        var commits = DemoChat(
            id: commitsChat, title: "Summarize this week's commits", workspace: "/Users/you/Projects/pebble-web",
            updated: ago(2 * 3600))
        commits.messages = [
            DemoMessage(
                id: "m-commits-1", role: "user", content: "Summarize this week's commits for the changelog.",
                created: ago(2 * 3600 + 50)),
            DemoMessage(
                id: "m-commits-reply", role: "assistant",
                content: """
                    This week in pebble-web:

                    - **Sign-in**: the session now survives a browser restart.
                    - **Settings**: the theme follows the system by default.
                    - **Speed**: the conversation list opens about twice as fast.

                    12 commits by 3 people; no breaking changes. To list them yourself:

                    ```sh
                    git log --since="1 week ago" --oneline
                    ```

                    I kept the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) headings, so it pastes into \
                    CHANGELOG.md as it is.
                    """, created: ago(2 * 3600), runID: "r-commits"),
        ]
        runs.append(
            DemoRun(
                id: "r-commits", chatID: commitsChat, state: "completed", steps: 6, elapsed: 38.2, error: nil,
                created: ago(2 * 3600 + 48), updated: ago(2 * 3600), messageID: "m-commits-reply"))
        chats.append(commits)

        // 5. Failed. Its note's second sentence is written for the model; the phone leaves it out (PersonNote).
        var deploy = DemoChat(
            id: deployChat, title: "Deploy the preview build", workspace: "/Users/you/Projects/pebble-web",
            updated: ago(26 * 3600))
        deploy.messages = [
            DemoMessage(
                id: "m-deploy-1", role: "user", content: "Start the preview build so I can check it on my phone.",
                created: ago(26 * 3600 + 30)),
            DemoMessage(
                id: "m-deploy-reply", role: "assistant",
                content: "I tried to start the preview, but port 4173 is already in use by another program.",
                created: ago(26 * 3600), runID: deployRun),
        ]
        runs.append(
            DemoRun(
                id: deployRun, chatID: deployChat, state: "failed", steps: 3, elapsed: 14.6,
                error: "The preview server didn't start: port 4173 is already in use. Do not claim the preview is live.",
                created: ago(26 * 3600 + 28), updated: ago(26 * 3600), messageID: "m-deploy-reply"))
        chats.append(deploy)

        // 6. Finished, no project.
        var weather = DemoChat(id: weatherChat, title: "Weather in Lisbon this weekend", workspace: nil, updated: ago(3 * 86400))
        weather.messages = [
            DemoMessage(
                id: "m-weather-1", role: "user", content: "What's the weather in Lisbon this weekend?",
                created: ago(3 * 86400 + 20)),
            DemoMessage(
                id: "m-weather-reply", role: "assistant",
                content: "Saturday: sunny, 24 °C, a light breeze from the north [S1].\nSunday: clouds in the morning, then sun, 22 °C [S1, S2].",
                created: ago(3 * 86400), runID: "r-weather"),
        ]
        runs.append(
            DemoRun(
                id: "r-weather", chatID: weatherChat, state: "completed", steps: 2, elapsed: 6.1, error: nil,
                created: ago(3 * 86400 + 18), updated: ago(3 * 86400), messageID: "m-weather-reply"))
        chats.append(weather)

        // 7. Held for verification: the change is made, its tests haven't run (Pebble's three decisions wait).
        var theme = DemoChat(
            id: themeChat, title: "Add a dark mode toggle", workspace: "/Users/you/Projects/pebble-web", updated: ago(2 * 60))
        theme.messages = [
            DemoMessage(
                id: "m-theme-1", role: "user", content: "Add a dark mode toggle to the settings page.", created: ago(14 * 60)),
            DemoMessage(
                id: "m-theme-reply", role: "assistant",
                content: "I added a toggle to the settings page: it follows the system until you choose light or dark. I couldn't run the tests yet, so the change isn't verified.",
                created: ago(2 * 60), runID: themeRun),
        ]
        theme.actions = [
            DemoAction(
                id: themeEdit, chatID: themeChat, kind: "edit", status: "applied",
                payload: [
                    "path": "src/settings/ThemeToggle.tsx", "root": "/Users/you/Projects/pebble-web", "baseline": "9f2c41d0",
                    "before": "export function ThemeToggle() {\n  return null;\n}\n",
                    "diff": "@@ -1,3 +1,9 @@\n export function ThemeToggle() {\n-  return null;\n+  const [theme, setTheme] = useTheme();\n+  return (\n+    <Switch checked={theme === 'dark'} onChange={(on) => setTheme(on ? 'dark' : 'light')}>\n+      Dark mode\n+    </Switch>\n+  );\n }",
                    "result": ["status": "applied", "hash": "4be1a7c2"],
                ], created: ago(5 * 60))
        ]
        runs.append(
            DemoRun(
                id: themeRun, chatID: themeChat, state: "verification_required", steps: 9, elapsed: 72.4,
                error: "The change to src/settings/ThemeToggle.tsx has no passing test run yet.", created: ago(14 * 60),
                updated: ago(2 * 60), messageID: "m-theme-reply"))
        chats.append(theme)

        // 8. An uncertain step: Mail stopped answering after the Send press. Its window is paused until you check it.
        var mail = DemoChat(id: mailChat, title: "Send the weekly update in Mail", workspace: nil, updated: ago(3 * 60))
        mail.messages = [
            DemoMessage(
                id: "m-mail-1", role: "user", content: "Send the weekly update to the team from Mail, using my draft in Notes.",
                created: ago(20 * 60)),
            DemoMessage(
                id: "m-mail-reply", role: "assistant",
                content: "I copied the update into a new message in Mail and pressed Send, but Mail stopped answering before I could check that it went.",
                created: ago(3 * 60), runID: mailRun),
        ]
        runs.append(
            DemoRun(
                id: mailRun, chatID: mailChat, state: "needs_reconciliation", steps: 6, elapsed: 41,
                error: "Pebble lost track of the last press in Mail before it could confirm it.", created: ago(20 * 60),
                updated: ago(3 * 60), messageID: "m-mail-reply"))
        chats.append(mail)

        // 9. Finished, with the command it started still running (it waits for an answer) and one it lost track of.
        var site = DemoChat(
            id: siteChat, title: "Run the docs site locally", workspace: "/Users/you/Projects/pebble-docs",
            updated: ago(50 * 60))
        site.messages = [
            DemoMessage(
                id: "m-site-1", role: "user", content: "Start the docs site so I can look at it.", created: ago(52 * 60)),
            DemoMessage(
                id: "m-site-reply", role: "assistant",
                content: "The docs site is running with `npm run dev`. It asks whether to open a browser: answer it below, or stop it when you're done.",
                created: ago(50 * 60), runID: siteRun),
        ]
        runs.append(
            DemoRun(
                id: siteRun, chatID: siteChat, state: "completed", steps: 4, elapsed: 23.0, error: nil,
                created: ago(52 * 60), updated: ago(50 * 60), messageID: "m-site-reply"))
        chats.append(site)

        return (chats, runs)
    }
}

extension DemoData {
    /// What the earlier runs did, as run_activity items (run_activity.py: seq, at, kind, label, detail, duration, status).
    static func activity(now: Date) -> [String: [JSONValue]] {
        func item(
            _ n: Int, _ at: Double, _ kind: String, _ label: String, _ duration: Double?, _ status: String = "done",
            detail: String? = nil, activity: String? = nil
        ) -> JSONValue {
            [
                "seq": .int(n * 64), "at": .double(at), "kind": .string(kind), "label": .string(label),
                "detail": detail.map(JSONValue.string) ?? .null, "duration": duration.map(JSONValue.double) ?? .null,
                "status": .string(status), "activity": activity.map(JSONValue.string) ?? .null,
            ]
        }
        return [
            // Lane Y: six steps, as its end line says (U-45), with Pebble's activity classes, so the reads and searches
            // fold into one "Explored" row as on the Mac (activity.ts groupRows).
            "r-commits": [
                item(1, 0.4, "context", "Using the project's conventions (AGENTS.md)", 0.2),
                item(2, 1.1, "tool", "Reading the last week of commits", 3.2, activity: "reading"),
                item(3, 4.6, "tool", "Searching for breaking changes", 1.4, activity: "searching"),
                item(4, 6.1, "tool", "Reading CHANGELOG.md", 0.6, activity: "reading"),
                item(5, 6.9, "tool", "Counting commits by author", 1.8,
                    detail: "git shortlog -sn --since=\"1 week ago\"", activity: "running"),
                item(6, 8.9, "tool", "Reading src/settings/theme.ts", 0.4, activity: "reading"),
                item(7, 9.4, "check", "Checked the reply", 0.3),
                item(8, 9.9, "model", "ChatGPT responded", 28.2),
            ],
            readmeRun: [
                item(1, 0.5, "tool", "Reading README.md", 0.8),
                item(2, 1.6, "tool", "Editing README.md", 2.1),
                item(3, 4.1, "approval", "Waiting for your review: npm test", nil, "running"),
                // Lane Y: the helper agents Details › Task lists (DemoDetails); Pebble's activity shows each as a step.
                item(4, 4.3, "child", "Started a helper: Link checker", nil, "running"),
                item(5, 4.4, "child", "Started a helper: Proofreader", 12.9),
            ],
            emailsRun: [item(1, 0.6, "model", "Planning the sequence", 7.9), item(2, 8.7, "note", "Asked you a question", nil)],
            deployRun: [
                item(1, 0.3, "tool", "Reading package.json", 0.5),
                item(2, 1.0, "tool", "Starting the preview (npm run preview)", 12.4, "failed",
                    detail: "Port 4173 is already in use by another program."),
            ],
            "r-weather": [item(1, 0.2, "tool", "Looking up current weather", 4.8)],
            themeRun: [
                item(1, 0.4, "tool", "Reading src/settings/Settings.tsx", 0.9),
                item(2, 1.6, "tool", "Editing src/settings/ThemeToggle.tsx", 2.4),
                item(3, 4.4, "check", "Checking the change", 1.2, "failed", detail: "No test run covers this change yet."),
            ],
            mailRun: [
                item(1, 0.5, "tool", "Reading the draft in Notes", 1.1),
                item(2, 2.0, "tool", "Writing the message in Mail", 6.3),
                item(3, 9.0, "tool", "Pressing Send in Mail", nil, "failed", detail: "Mail stopped answering."),
            ],
            siteRun: [
                item(1, 0.3, "tool", "Reading package.json", 0.4),
                item(2, 1.0, "tool", "Starting the docs site (npm run dev)", 3.1),
            ],
        ]
    }
}
