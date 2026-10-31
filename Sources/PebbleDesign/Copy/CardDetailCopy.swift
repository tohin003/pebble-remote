import Foundation
import PebbleProtocol

/// What a review card holds beyond its sentence and its exact detail, in Pebble's words and order, for a person reading it
/// on the phone before deciding: the diff of an edit ("View diff"), the check an ad hoc test adds ("View the check"), a
/// command's risk, folder and plan, a connector call's arguments, and Pebble's typed review under "Technical details".
///
/// Ported from Pebble's window (read-only Pebble checkout 1.9.28): the card body in `src/App.vue` (the description
/// lines, the diff, the check, the command preview, the arguments) and `src/components/ActionReview.vue` (every
/// pending card's typed review). The parts of ActionReview that read back a settled card are left out: the phone shows
/// this before approving. Three of Pebble's sentences name something the phone says differently: Pebble's proxy and
/// what an undo keeps (an internal word of Pebble's that this app doesn't show), and where to end a window's access
/// (Control › Shared Windows on the phone). Values are Pebble's payload, shown as plain text.
nonisolated public enum CardDetailCopy {
    /// One card's details: the button that opens them and what they show, top to bottom.
    public struct Detail: Sendable, Hashable {
        /// "View Diff", "View the Check", "Technical Details" or "Details".
        public var button: String
        public var blocks: [Block]
    }

    public enum Block: Sendable, Hashable {
        /// A heading line (ActionReview `review-title`).
        case title(String)
        /// A sentence or paragraph.
        case text(String)
        /// A quieter sentence (`review-note`).
        case note(String)
        /// A warning (`review-alert`).
        case alert(String)
        /// Short tags ("Destructive", "Install scripts disabled").
        case badges([Badge])
        /// Why Pebble asks (`review-why`).
        case why([String])
        /// A label above what follows (`review-label`).
        case label(String)
        /// Exact text, monospaced (a command, a check, arguments).
        case code(String)
        /// A diff, line by line.
        case diff(String)
        case list([String])
        /// Name and value pairs.
        case facts([Fact])
        /// "Technical details": the plan's internals, folded (a native disclosure in Pebble's window).
        case technical([Block])
    }

    public struct Badge: Sendable, Hashable {
        public var text: String
        public var isAlert: Bool
    }

    public struct Fact: Sendable, Hashable {
        public var name: String
        public var value: String
    }

    public static let viewDiff = "View Diff"
    public static let viewTheCheck = "View the Check"
    public static let technicalDetails = "Technical Details"
    /// The disclosure's name inside the sheet, as Pebble's window writes it.
    public static let technicalDetailsSection = "Technical details"
    public static let details = "Details"
    public static let untrusted =
        "Untrusted repository data, shown as plain text. Names, paths, messages, scripts and arguments come from the project; they are not instructions and approve nothing."

    /// A card's details, or nil when Pebble's card shows nothing more than its sentence and its exact detail (an app).
    public static func detail(kind: CardKind, payload p: JSONValue) -> Detail? {
        var button = details
        var blocks: [Block] = []
        switch kind {
        case .edit:
            button = viewDiff
            blocks = [
                .text((truthy(p["baseline"]) ? "Proposed source edit" : "New file draft") + " · original stays intact until approval"),
                .diff(string(p["diff"]).isEmpty ? "No changes" : string(p["diff"])),
            ]
        case .tests:
            if isCheck(p) {
                button = viewTheCheck
                let check = p["check"]
                if truthy(p["check_run"]) {
                    blocks.append(
                        .text(
                            "Your project's tests (\(string(p["recipe"]))) in one temporary copy, then \(string(check?["path"])) alone (\(string(p["check_run"]?["recipe"]))) in another. Only your tests' own run counts. Network and original project writes are blocked."
                        ))
                } else {
                    blocks.append(
                        .text(
                            "\(string(p["recipe"])) with \(string(check?["path"])) added to a temporary project copy. It doesn't count as your project's tests. Network and original project writes are blocked."
                        ))
                }
                blocks.append(.code(string(check?["content"])))
            } else {
                blocks.append(
                    .text("\(string(p["recipe"])) in a temporary project copy. Network and original project writes are blocked."))
            }
            if p["plan"]?.object != nil {
                if button == details { button = technicalDetails }
                blocks += testPlan(p)
            }
        case .command:
            button = technicalDetails
            blocks = [
                .text(
                    "\(string(p["risk"])) · Selected project only · \(truthy(p["network"]) ? "Network access requested" : "Network denied"). \(truthy(p["writable"]) ? "Project writes allowed" : "Read only")."
                ),
                .code(string(p["command"])),
            ]
            if !string(p["root"]).isEmpty { blocks.append(.note(string(p["root"]))) }
            blocks += commandPlan(p)
        case .plugin:
            blocks = [
                .text("External tool call · \(string(p["url"])). Review the arguments before allowing this call."),
                .code(prettyJSON(p["arguments"] ?? .null)),
            ]
        case .git:
            button = technicalDetails
            blocks = gitPlan(p)
        case .worktree:
            button = technicalDetails
            blocks = worktree(p)
        case .install:
            button = technicalDetails
            blocks = install(p)
        case .shell: blocks = shell(p)
        case .file: blocks = file(p)
        case .screen: blocks = screenPress(p)
        case .url: blocks = link(p)
        case .screenGrant: blocks = screenGrant(p)
        case .browserGrant: blocks = browserGrant(p)
        case .appAction: blocks = appAction(p)
        case .screenRaise: blocks = screenRaise(p)
        default: return nil
        }
        return blocks.isEmpty ? nil : Detail(button: button, blocks: blocks)
    }

    // MARK: - ActionReview.vue, kind by kind

    static func gitPlan(_ p: JSONValue) -> [Block] {
        let b = p["bindings"] ?? .null
        let who = b["identity"] ?? .null
        let findings = p["sensitive_findings"]?.array ?? []
        let remote = p["remote"]?.string != nil || b["remote_path"]?.string != nil
        let operation = text(p["operation"], 40).isEmpty ? "unknown operation" : text(p["operation"], 40)
        let destructive = p["destructive"]?.bool == true, publication = p["publication"]?.bool == true
        var blocks: [Block] = [.title("Git \(operation)")]
        var badges: [Badge] = []
        if destructive { badges.append(Badge(text: "Destructive", isAlert: true)) }
        if publication { badges.append(Badge(text: "Publication", isAlert: true)) }
        if !badges.isEmpty { blocks.append(.badges(badges)) }
        let summary = text(p["summary"], 4000)
        if !summary.isEmpty { blocks.append(.text(summary)) }
        if destructive {
            // Pebble's last sentence names its record of the change with a word this app doesn't show.
            blocks.append(
                .note(
                    "Destructive: this removes or rewrites work, so it needs your approval in every permission mode. Pebble keeps what an undo needs."
                ))
        }
        if publication {
            blocks.append(
                .note("Publication: this copies commits into another repository. Only local bare repositories are supported."))
        }
        let paths = entries(b["paths"])
        if !paths.isEmpty {
            blocks.append(.label("Selected paths (\(paths.count))"))
            blocks.append(.list(paths.prefix(maxPaths).map(pathRow)))
            if paths.count > maxPaths { blocks.append(.note("\(paths.count - maxPaths) more path(s) not shown.")) }
        }
        if let message = p["message"]?.string {
            blocks += [.label("Commit message (plain text)"), .code(text(.string(message), 4000))]
        }
        if !findings.isEmpty {
            blocks.append(.label("Sensitive findings (values are never shown)"))
            blocks.append(
                .list(
                    findings.prefix(20).map { found in
                        let line = found["line"].map { $0.isNull ? "whole file" : "line " + text($0, 20) } ?? "whole file"
                        return "\(text(found["path"], 500)) · \(line) · \(text(found["kind"], 60))"
                    }))
        }
        let effects = lines(p["effects"], maxRows)
        if !effects.isEmpty { blocks += [.label("Effects"), .list(effects)] }
        var technical: [Block] = [.note(untrusted)]
        var tags: [Badge] = []
        if p["requires_review"]?.bool == true { tags.append(Badge(text: "Needs native review", isAlert: false)) }
        tags.append(Badge(text: "hooks_run: " + (p["hooks_run"]?.bool == false ? "false" : "not reported as false"), isAlert: false))
        let network = p["network"]?.bool == false ? "false" : (text(p["network"], 80).isEmpty ? "not reported" : text(p["network"], 80))
        tags.append(Badge(text: "network: " + network, isAlert: false))
        technical.append(.badges(tags))
        var headRef = ""
        if let ref = b["head_ref"]?.string { headRef = branch(ref) } else if b["head_ref"] != nil { headRef = "detached HEAD" }
        var author = ""
        if !text(who["name"], 200).isEmpty || !text(who["email"], 254).isEmpty {
            author = text(who["name"], 200) + " <" + text(who["email"], 254) + ">"
                + (text(who["source"], 40).isEmpty ? "" : " · from " + text(who["source"], 40))
        }
        var moves = ""
        if let ref = b["remote_ref"]?.string {
            let old = truthy(b["old_oid"]) ? short(b["old_oid"]) : "absent"
            let new = short(b["new_oid"])
            moves = text(.string(ref), 300) + ": " + old + " → "
                + (!new.isEmpty ? new : b["delete"]?.bool == true ? "absent (deleted)" : "not reported")
        }
        var upstream = ""
        if let up = b["upstream"], up.object != nil { upstream = text(up["remote"], 100) + " · " + text(up["merge"], 300) }
        let facts = rows([
            ("Repository root", text(p["root"], 1000)),
            ("Branch", headRef),
            ("HEAD", short(b["head_commit"])),
            ("Author", author),
            ("New branch", p["operation"]?.string == "commit" ? text(p["branch"], 200) : ""),
            ("Local branch", p["operation"]?.string == "push" ? text(p["branch"], 200) : ""),
            ("Branch name", text(p["name"], 200)),
            ("Target ref", text(b["target_ref"] ?? b["branch_ref"], 300)),
            ("Source ref", text(b["source_ref"], 300)),
            ("Switch after creating", p["switch"]?.bool.map(flag) ?? ""),
            ("Remote", text(p["remote"], 100)),
            ("Remote branch", text(p["remote_branch"], 200)),
            (
                "Remote URL kind",
                remote
                    ? (b["remote_path"]?.string != nil ? "local bare repository (network remotes are refused)" : "not reported")
                    : ""
            ),
            ("Remote repository", text(b["remote_path"], 1000)),
            ("Remote ref moves", moves),
            (
                "Forced update",
                b["force"]?.bool == true
                    ? "yes: only while the remote still points at " + short(b["old_oid"]) + "; " + number(b["dropped"])
                        + " remote commit(s) leave the branch" : ""
            ),
            ("Remote-tracking branch", b["tracking"]?.array.map { text($0.first, 300) } ?? ""),
            ("Sets upstream", upstream),
            ("Commits copied", b["commits"].map { $0.isNull ? "" : number($0) } ?? ""),
            (
                "Sensitive findings",
                p["sensitive_findings"]?.array != nil ? (findings.isEmpty ? "none reported" : "\(findings.count) (listed below)") : ""
            ),
            // Pebble's own name for this row uses a word this app doesn't show.
            ("Undo of change", text(p["undo_of"], 40)),
            ("Undoes operation", text(p["undo_operation"], 40)),
            ("Plan ID", text(p["plan_id"], 40)),
            ("Plan hash", short(p["plan_hash"], 16)),
        ])
        if !facts.isEmpty { technical.append(.facts(facts)) }
        blocks.append(.technical(technical))
        return blocks
    }

    static func worktree(_ p: JSONValue) -> [Block] {
        let operation = p["operation"]?.string
        let allocate = operation == "allocate_child_worktree", retire = operation == "retire_child_worktree"
        var blocks: [Block] = [
            .title(
                allocate
                    ? "Allocate a child worktree"
                    : retire ? "Retire a child worktree" : "Unknown worktree operation: " + text(p["operation"], 60))
        ]
        if allocate {
            blocks.append(
                .note(
                    "Dirty work is not copied: uncommitted project changes stay where they are and are never copied or discarded. The child writes only inside this folder."
                ))
            let disclosure = text(p["disclosure"], 2000)
            if !disclosure.isEmpty { blocks.append(.text(disclosure)) }
        }
        let effects = lines(p["effects"], maxRows)
        if !effects.isEmpty { blocks += [.label("Effects"), .list(effects)] }
        var technical: [Block] = [.note(untrusted)]
        let facts = rows([
            ("Child agent", text(p["agent_id"], 128)),
            ("Generation", text(p["generation"], 20)),
            ("Root run", text(p["run_id"], 128)),
            ("Worktree ID", text(p["worktree_id"], 40)),
            ("Base commit", short(p["base_commit"])),
            ("Folder", text(p["path"], 1000)),
            ("Repository root", text(p["root"], 1000)),
        ])
        if !facts.isEmpty { technical.append(.facts(facts)) }
        blocks.append(.technical(technical))
        return blocks
    }

    static func install(_ p: JSONValue) -> [Block] {
        let allowlisted = p["network"]?.string == "allowlisted_registry_only"
        let network = text(p["network"], 80).isEmpty ? "not reported" : text(p["network"], 80)
        var blocks: [Block] = [
            .title("Install dependencies from the lockfile"),
            .badges([
                Badge(text: "Install scripts disabled", isAlert: false),
                Badge(
                    text: allowlisted ? "Network: allowlisted registries only" : "Unexpected network value: " + network,
                    isAlert: !allowlisted),
            ]),
        ]
        let summary = text(p["summary"], 2000)
        if !summary.isEmpty { blocks.append(.text(summary)) }
        // Pebble's sentence names its proxy with a word this app doesn't show; only that changes.
        blocks.append(
            .note(
                "Install scripts disabled: npm runs with --ignore-scripts, and pip installs hash-pinned binary wheels only. The network reaches only the registries below, on port 443, through Pebble's proxy. Files go to a managed folder outside the project."
            ))
        blocks.append(.label("Registries"))
        let registries = entries(p["registries"]).prefix(8).map { item -> String in
            if let pair = item.array { return text(pair.first, 253) + ":" + text(pair.dropFirst().first, 8) }
            return text(item, 300)
        }
        blocks.append(registries.isEmpty ? .note("No registry was reported.") : .list(Array(registries)))
        let effects = lines(p["effects"], maxRows)
        if !effects.isEmpty { blocks += [.label("Effects"), .list(effects)] }
        var technical: [Block] = [.note(untrusted)]
        let facts = rows([
            ("Kind", text(p["kind"], 40)),
            ("Environment ID", text(p["environment_id"], 40)),
            ("Lockfile digest", short(p["lock_digest"])),
            ("Manifest digest", short(p["manifest_digest"])),
            ("Packages", number(p["packages"])),
            ("Size limit", bytes(p["size_limit"])),
            ("Timeout", seconds(p["timeout"])),
            ("Project root", text(p["root"], 1000)),
        ])
        if !facts.isEmpty { technical.append(.facts(facts)) }
        blocks.append(.technical(technical))
        return blocks
    }

    static func shell(_ p: JSONValue) -> [Block] {
        var blocks: [Block] = []
        let reasons = lines(p["reasons"], 12, 400)
        if !reasons.isEmpty { blocks.append(.why(reasons)) }
        let cwd = text(p["cwd"], 500)
        blocks.append(.label("Command (runs in Pebble's sandbox" + (cwd.isEmpty ? "" : ", in " + cwd) + ")"))
        blocks.append(.code(text(p["command"], 8000)))
        let hosts = lines(p["hosts"], 16, 253)
        if !hosts.isEmpty { blocks += [.label("Network (only these hosts)"), .list(hosts)] }
        let folders = lines(p["folders"], 16, 1024)
        if !folders.isEmpty { blocks += [.label("May write outside the workbench"), .list(folders)] }
        if !entries(p["snapshot_paths"]).isEmpty {
            blocks.append(.note("Pebble keeps a copy of what this may change first, so you can undo it."))
        }
        if p["always_offered"]?.bool == false {
            blocks.append(.note("Pebble asks about this every time; it cannot be allowed always."))
        }
        return blocks
    }

    static func file(_ p: JSONValue) -> [Block] {
        let edit = text(p["op"], 20) == "edit"
        var blocks: [Block] = [.label((edit ? "Edit " : "Write ") + text(p["path"], 1024))]
        if edit {
            blocks += [.label("Replace"), .code(text(p["old_string"], 1000)), .label("With"), .code(text(p["new_string"], 1000))]
        } else {
            blocks.append(.code(text(p["content"], 2000)))
        }
        blocks.append(.note("Pebble keeps a copy of the file first, so you can undo it."))
        let gated = text(p["gated"], 200)
        if !gated.isEmpty { blocks.append(.note("\(gated) is asked about every time.")) }
        return blocks
    }

    static func screenPress(_ p: JSONValue) -> [Block] {
        let review = p["review"] ?? .null, element = review["element"] ?? .null, window = review["window"] ?? .null
        let role = text(element["role"], 40).replacingOccurrences(of: "^AX", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^Unknown$", with: "", options: .regularExpression)
        let action = text(review["action"], 20), label = text(element["label"], 120)
        let title = text(window["title"], 200), origin = text(window["origin"], 300)
        var blocks: [Block] = [
            .label("In the window \u{201C}\(title.isEmpty ? "untitled" : title)\u{201D}" + (origin.isEmpty ? "" : " (\(origin))") + ", as the app names it"),
            .text(
                "Pebble will \(action.isEmpty ? "act on" : action) \u{201C}\(label.isEmpty ? "an unlabelled " + (role.isEmpty ? "element" : role) : label)\u{201D}"
                    + (role.isEmpty ? "" : " (\(role))") + "."),
        ]
        let typed = text(review["text"], 400)
        if !typed.isEmpty { blocks += [.label("Text"), .code(typed)] }
        let nearby = entries(review["context"]).map { text($0["label"], 80) }.filter { !$0.isEmpty }.prefix(8)
        if !nearby.isEmpty { blocks += [.label("Next to it on screen"), .list(Array(nearby))] }
        if review["consent"]?.string == "foreground_input" {
            blocks.append(
                .note(
                    "This uses your mouse and keyboard in that window. Approving it also lets Pebble use them there while the window stays allowed (up to 15 minutes); any key or mouse movement of yours pauses it."
                ))
        }
        let reasons = lines(review["reasons"], 8, 120)
        let sending = reasons.contains {
            ["label_commit_word", "form_submit", "transfer", "enter_submits", "newline_submits", "leaves_origin"].contains($0)
        }
        let commit = review["class"]?.string != "local" && review["class"]?.string != "input"
        if commit && sending {
            blocks.append(.note("This may send, submit, save, delete or buy, so it waits for you. Pebble can't undo it and never retries it."))
        } else if commit {
            blocks.append(.note("Pebble can't undo a press, so this one waits for you. It is never retried."))
        }
        return blocks
    }

    static func link(_ p: JSONValue) -> [Block] {
        var blocks: [Block] = []
        let reasons = lines(p["reasons"], 4, 200)
        if !reasons.isEmpty { blocks.append(.why(reasons)) }
        let route = p["route"]?.string
        if route == "table" || route == "opensearch" {
            blocks.append(.text("Search \(text(p["site"], 253)) for \u{201C}\(text(p["query"], 300))\u{201D}"))
        }
        let browser = text(p["browser"]?["name"], 128)
        blocks.append(.label("Address (opens in \(browser.isEmpty ? "your default browser" : browser))"))
        blocks.append(.code(text(p["url"], 2048)))
        let why = text(p["why"], 300)
        if !why.isEmpty { blocks.append(.text("Pebble says: \(why)")) }
        blocks.append(.note("Pebble only asks macOS to open it; it can't see the page."))
        return blocks
    }

    static func screenGrant(_ p: JSONValue) -> [Block] {
        let app = text(p["app"], 128), window = text(p["title"], 200)
        var blocks: [Block] = [
            .label("\(app.isEmpty ? "An app" : app), the window \u{201C}\(window.isEmpty ? "untitled" : window)\u{201D} (as the app names it)")
        ]
        let why = text(p["why"], 300)
        if !why.isEmpty { blocks.append(.text("Pebble says: \(why)")) }
        blocks.append(.label("In this conversation, for up to \(minutes(p)) minutes, Pebble could"))
        let can = abilities(p, sites: false)
        blocks.append(.list(can))
        if can.count > 1 {
            blocks.append(
                .note(
                    p["full_access"]?.bool == true
                        ? "In Full access Pebble checks its first use of your mouse and keyboard in this window against your messages; otherwise it asks you once."
                        : "Its first use of your mouse and keyboard in this window asks you once."))
        }
        switch elsewhere(p) {
        case "on another desktop":
            blocks.append(.note("This window is on another desktop, so what Pebble reads there may be out of date."))
        case "":
            break
        default:
            blocks.append(.note("This window is minimized; Pebble asks before bringing it forward."))
        }
        // Pebble's window says where to end access on the Mac; the phone names its own place.
        blocks.append(
            .note(
                "Only this window. Pebble stops at sign-ins, codes and checks and hands them to you. End access any time in Control › Shared Windows."
            ))
        return blocks
    }

    static func browserGrant(_ p: JSONValue) -> [Block] {
        let act = lines(p["sites"], 8, 300)
        let read = lines(p["read"], 16, 300).filter { !act.contains($0) }
        let window = p["route"]?.string == "window"
        let browser = text(p["browser"], 40), browserName = text(p["browser_name"], 40)
        var blocks: [Block] = [
            .label(
                window
                    ? "In a new \(browserName.isEmpty ? "browser" : browserName) window that Pebble reads through Accessibility, for \(minutes(p)) minutes, Pebble could act on"
                    : "In Pebble's own tab\(browser.isEmpty ? " in your browser" : " in " + browser), for \(minutes(p)) minutes, Pebble could act on"),
            .list(act),
        ]
        if !read.isEmpty { blocks += [.label("And only read"), .list(read)] }
        blocks += [.label("Starting at"), .code(text(p["url"], 2048))]
        let why = text(p["why"], 300)
        if !why.isEmpty { blocks.append(.text("Pebble says: \(why)")) }
        blocks.append(.list(abilities(p, sites: true)))
        if window { blocks.append(.note("Pebble reads only that window's page, and only while it shows these sites.")) }
        blocks.append(
            .note(
                "Pebble's steps there run the site's own code. It stops at sign-ins, payments and checks and hands them to you; anything that sends, buys or deletes still waits for you."
            ))
        return blocks
    }

    static func appAction(_ p: JSONValue) -> [Block] {
        let args = p["args"] ?? .null
        let app = text(p["app"], 40), summary = text(p["summary"], 300)
        var blocks: [Block] = []
        let reasons = lines(p["reasons"], 4, 200)
        if !reasons.isEmpty { blocks.append(.why(reasons)) }
        blocks.append(.text(summary.isEmpty ? "Pebble will ask \(app.isEmpty ? "an app" : app) to do this." : summary))
        let fields: [(String, String)] = [
            ("to", "To"), ("subject", "Subject"), ("title", "Title"), ("name", "Shortcut"), ("folder", "Folder"),
            ("calendar", "Calendar"), ("start", "Starts"), ("end", "Ends"), ("query", "Search"), ("path", "Path"),
        ]
        for (key, name) in fields {
            if let list = args[key]?.array {
                blocks += [.label(name), .code(lines(.array(list), 20, 200).joined(separator: ", "))]
            } else if args[key]?.string != nil {
                blocks += [.label(name), .code(text(args[key], 300))]
            }
        }
        let body = text(args["text"], 4000)
        if !body.isEmpty { blocks += [.label("Text"), .code(body)] }
        blocks.append(
            .note(
                "Pebble asks \(app.isEmpty ? "the app" : app) through its own scripting. It never sends mail or deletes anything this way, and macOS asks you once per app."
            ))
        return blocks
    }

    static func screenRaise(_ p: JSONValue) -> [Block] {
        let app = text(p["app"], 128), window = text(p["title"], 200)
        let place = elsewhere(p)
        return [
            .label("\(app.isEmpty ? "An app" : app), the window \u{201C}\(window.isEmpty ? "untitled" : window)\u{201D} (as the app names it)"),
            .text(
                "Bring this window forward so Pebble can read it? It is \(place.isEmpty ? "out of view" : place), and macOS may switch to its desktop."
            ),
            .note("Pebble asks once in this conversation; after that it brings this window forward without asking."),
        ]
    }

    /// A typed command plan (ActionReview `command`).
    static func commandPlan(_ p: JSONValue) -> [Block] {
        var blocks: [Block] = []
        if let review = p["guard_review"]?.string { blocks.append(.why([text(.string(review), 300)])) }
        if let effect = p["effect"]?.string { blocks.append(.why([text(.string(effect), 600)])) }
        guard let plan = p["plan"], plan.object != nil else {
            blocks.append(
                .note(
                    "Unplanned command: the text could not be expressed as an exact argv plan, so its executable is resolved when it runs. Review the command text above carefully."
                ))
            blocks.append(.technical([.note(untrusted)]))
            return blocks
        }
        blocks.append(.title("Typed command plan · executable pinned at review and re-verified before it runs"))
        let steps = entries(plan["steps"]).prefix(4)
        var technical: [Block] = [.note(untrusted)]
        for (index, step) in steps.enumerated() {
            blocks += [.label("Step \(index + 1) argv (exact, no shell)"), .code(argv(step["argv"]))]
            let env = (step["env"]?.object ?? [:]).sorted { $0.key < $1.key }.prefix(16)
                .map { text(.string($0.key), 64) + "=" + text($0.value, 200) }
            let facts = rows([
                ("Executable realpath", text(step["executable"]?["realpath"], 1000)),
                ("Executable SHA-256", short(step["executable"]?["sha256"])),
                ("Working folder", text(step["cwd"], 200)),
                ("Environment", env.joined(separator: ", ")),
                ("Input", step["stdin"]?.string == "pty" ? "interactive terminal" : ""),
            ])
            if !facts.isEmpty { technical.append(.facts(facts)) }
        }
        let network = plan["network"] ?? .null, resources = plan["resources"] ?? .null
        let writable = lines(plan["writable"], 16).joined(separator: ", ")
        let mode = network["mode"]?.string
        let facts = rows([
            ("Pipeline", text(plan["pipeline"], 20)),
            ("Writable", writable.isEmpty ? "read-only" : writable),
            ("Network", mode == "none" ? "denied" : mode == "broker" ? "reviewed destinations only" : text(network["mode"], 20)),
            ("Process model", plan["process_model"]?.string == "single" ? "one process, no children" : text(plan["process_model"], 20)),
            ("Timeout", seconds(resources["timeout"])),
            ("CPU", seconds(resources["cpu_seconds"])),
            ("Memory", truthy(resources["memory_mb"]) ? text(resources["memory_mb"], 8) + " MB" : ""),
            ("Processes", text(resources["nproc"], 6)),
            ("Output limit", bytes(resources["output_bytes"])),
            ("Plan hash", short(plan["plan_hash"])),
        ])
        if !facts.isEmpty { technical.append(.facts(facts)) }
        blocks.append(.technical(technical))
        let destinations = entries(network["destinations"]).prefix(16).compactMap { item -> String? in
            guard let pair = item.array else { return nil }
            return text(pair.first, 253) + ":" + text(pair.dropFirst().first, 6)
        }
        if !destinations.isEmpty {
            blocks += [.label("Network destinations (the only hosts it can reach)"), .list(destinations)]
        }
        let credentials = entries(network["credentials"]).prefix(8).map { item -> String in
            let destination = item["destination"]?.array.map { text($0.first, 253) } ?? ""
            return text(item["ref"], 128) + " → " + destination + " " + lines(item["methods"], 6).joined(separator: "/") + " "
                + text(item["path_prefix"], 256)
        }
        if !credentials.isEmpty {
            blocks.append(
                .alert(
                    "Uses saved command credentials. The value is added by Pebble's broker on these routes only and is never visible to the command."
                ))
            blocks.append(.list(Array(credentials)))
        }
        if plan["interactive"]?.bool == true {
            blocks.append(
                .note("Interactive: the model may type into this command's terminal, except at password prompts, which only you can answer."))
        }
        return blocks
    }

    /// A test recipe's plan (ActionReview `tests`).
    static func testPlan(_ p: JSONValue) -> [Block] {
        let plan = p["plan"] ?? .null, executable = plan["executable"] ?? .null
        let recipe = text(plan["recipe"] ?? p["recipe"], 80)
        var blocks: [Block] = [
            .title("Test recipe \(recipe.isEmpty ? "unknown recipe" : recipe)"), .label("Command (argv)"), .code(argv(plan["argv"])),
        ]
        if let script = plan["script"]?.string { blocks += [.label("npm script (plain text)"), .code(text(.string(script), 4096))] }
        var technical: [Block] = [.note(untrusted)]
        let facts = rows([
            ("Recipe", recipe),
            ("Kind", text(plan["kind"], 20)),
            ("Working folder", plan["cwd"]?.string == "snapshot" ? "temporary project snapshot" : text(plan["cwd"], 200)),
            ("Timeout", seconds(plan["timeout"])),
            ("Output limit", bytes(plan["output_limit"])),
            ("Network", plan["network"]?.bool == false ? "denied" : text(plan["network"], 40).isEmpty ? "not reported" : text(plan["network"], 40)),
            ("Drafts in the snapshot", p["drafts"]?.array.map { String($0.count) } ?? ""),
        ])
        if !facts.isEmpty { technical.append(.facts(facts)) }
        let env = (plan["env"]?.object ?? [:]).sorted { $0.key < $1.key }.prefix(32)
            .map { Fact(name: text(.string($0.key), 200), value: text($0.value, 1000)) }
        if !env.isEmpty {
            technical += [.label("Environment ({temp} is a fresh per-run temporary folder)"), .facts(Array(env))]
        }
        let reads = lines(plan["toolchain_reads"], 16)
        if !reads.isEmpty { technical += [.label("Toolchain reads"), .list(reads)] }
        let entry = plan["entrypoint"]?.object != nil ? plan["entrypoint"] : nil
        let pinned = rows([
            ("Executable realpath", text(executable["realpath"], 1000)),
            ("Executable SHA-256", short(executable["sha256"])),
            ("npm entrypoint", entry.map { text($0["realpath"], 1000) } ?? ""),
            ("npm entrypoint SHA-256", entry.map { short($0["sha256"]) } ?? ""),
        ])
        if !pinned.isEmpty { technical.append(.facts(pinned)) }
        blocks.append(.technical(technical))
        return blocks
    }

    // MARK: - ActionReview's helpers: only reported facts become rows; an absent value is left out, never invented.

    static let maxPaths = 64
    static let maxRows = 50

    /// `text(value, limit)`: strings as they are, numbers and flags spelled out, anything else as JSON; long text cut
    /// with Pebble's note.
    static func text(_ value: JSONValue?, _ limit: Int = 2000) -> String {
        let result: String
        switch value {
        case .none, .null?: return ""
        case .string(let string)?: result = string
        case .int(let number)?: result = String(number)
        case .double(let number)?: result = number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .bool(let flag)?: result = flag ? "true" : "false"
        case let other?: result = (try? FrameCodec.jsonText(other)) ?? "Display data is unavailable."
        }
        guard result.count > limit else { return result }
        return String(result.prefix(limit)) + " … [truncated for display: \(limit) of \(result.count) characters shown]"
    }

    static func string(_ value: JSONValue?) -> String { text(value, Int.max) }

    /// JSON.stringify(value, null, 2): the arguments as Pebble's card shows them.
    static func prettyJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "Display data is unavailable." }
        return String(decoding: data, as: UTF8.self)
    }

    /// A hex digest's first characters; anything else as text.
    static func short(_ value: JSONValue?, _ size: Int = 12) -> String {
        if let hex = value?.string, (16...128).contains(hex.count), hex.allSatisfy(\.isHexDigit) {
            return String(hex.prefix(size))
        }
        return text(value, 200)
    }

    static func flag(_ value: Bool) -> String { value ? "yes" : "no" }

    static func number(_ value: JSONValue?) -> String {
        guard let number = value?.double, number.isFinite, value?.bool == nil else { return "not reported" }
        return text(value)
    }

    static func seconds(_ value: JSONValue?) -> String {
        guard let number = value?.double, number.isFinite else { return "not reported" }
        return text(value) + " seconds"
    }

    static func bytes(_ value: JSONValue?) -> String {
        guard let size = value?.double, size.isFinite, size >= 0 else { return "not reported" }
        for (unit, scale) in [("GiB", 1_073_741_824.0), ("MiB", 1_048_576.0), ("KiB", 1024.0)] where size >= scale {
            let scaled = (size / scale * 10).rounded() / 10
            let shown = scaled.rounded() == scaled ? String(Int(scaled)) : String(scaled)
            return "\(shown) \(unit)"
        }
        return text(value) + " bytes"
    }

    static func branch(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? text(.string(String(ref.dropFirst(11))), 200) : text(.string(ref), 300)
    }

    static func rows(_ pairs: [(String, String)]) -> [Fact] {
        pairs.filter { !$0.1.isEmpty }.map { Fact(name: $0.0, value: $0.1) }
    }

    static func entries(_ value: JSONValue?) -> [JSONValue] { value?.array ?? [] }

    static func lines(_ value: JSONValue?, _ limit: Int, _ size: Int = 1000) -> [String] {
        entries(value).prefix(limit).map { text($0, size) }
    }

    /// An argv as a shell would quote it for reading (never run): parts with spaces or quotes in JSON quotes.
    static func argv(_ value: JSONValue?) -> String {
        let all = entries(value)
        let shown = all.prefix(64).map { item -> String in
            let part = text(item, 1000)
            if part.isEmpty || part.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" }) {
                return (try? FrameCodec.jsonText(.string(part))) ?? part
            }
            return part
        }
        let more = all.count > 64 ? " … [\(all.count - 64) more arguments not shown]" : ""
        return text(.string(shown.joined(separator: " ")), 4000) + more
    }

    /// One selected path of a Git plan: "path · change · blob".
    static func pathRow(_ item: JSONValue) -> String {
        let previous = item["previous"] ?? .null, restore = item["restore"] ?? .null
        let after = item["index_after"] ?? item["tree_after"] ?? .null
        let change: String
        if let kind = item["kind"]?.string {
            change = kind
        } else if let value = item["previous"] {
            change = truthy(value) ? "discard; current bytes saved first" : "recreate the deleted file"
        } else if let value = item["restore"] {
            change = truthy(value) ? "restore the prior index entry" : "remove from the index"
        } else {
            change = "unknown"
        }
        let blob = item["blob_oid"] ?? previous["blob_oid"] ?? restore["oid"] ?? after["oid"]
        let blobText = blob == nil || blob == .null ? "none" : short(blob)
        return "\(text(item["path"], 500)) · \(text(.string(change), 80)) · blob \(blobText)"
    }

    static func minutes(_ p: JSONValue) -> Int {
        guard let ttl = p["ttl"]?.double, ttl.isFinite else { return 15 }
        return max(1, Int((ttl / 60).rounded()))
    }

    static func elsewhere(_ p: JSONValue) -> String {
        if p["off_space"]?.bool == true || p["reason"]?.string == "off_space" { return "on another desktop" }
        if p["minimized"]?.bool == true || p["reason"]?.string == "minimized" { return "minimized" }
        return ""
    }

    /// What Pebble could do in a window or on sites (`ABILITIES`, with Full access's and the sites' own press line).
    static func abilities(_ p: JSONValue, sites: Bool) -> [String] {
        lines(p["abilities"], 3, 10).compactMap { key -> String? in
            switch key {
            case "press" where sites:
                "press links and buttons (in Full access what your messages ask for runs at once and spending money waits for you; in the other modes sending, buying, deleting or leaving these sites waits for you)"
            case "press" where p["full_access"]?.bool == true:
                "press buttons (in Full access the presses your messages ask for run without asking; anything that may spend money waits for you)"
            case "look": "look around (focus, scroll, open and close sections)"
            case "fill": "fill in (choose options, tick boxes, type text; never a password, code or card field)"
            case "press":
                "press buttons (each press waits for you, except keypad keys, board squares, tabs, checkboxes and switches)"
            default: nil
            }
        }
    }

    static func isCheck(_ p: JSONValue) -> Bool { p["check"]?.object != nil && p["check"]?["content"]?.string != nil }

    /// JavaScript truthiness, as Pebble's templates test payload fields.
    static func truthy(_ value: JSONValue?) -> Bool {
        switch value {
        case .none, .null?: false
        case .bool(let flag)?: flag
        case .int(let number)?: number != 0
        case .double(let number)?: number != 0 && !number.isNaN
        case .string(let string)?: !string.isEmpty
        case .array?, .object?: true
        }
    }
}
