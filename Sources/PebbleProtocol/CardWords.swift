import Foundation

/// Pebble's own words for its review cards, ported from the desktop app so the phone says what Pebble says
/// (src/App.vue in the Pebble checkout: the card heading, `actionLead()`, `screenHeading()`, `siteNames()` and the
/// approve button). Payload fields are read tolerantly; a missing field falls back to the words Pebble's own review
/// panel uses (src/components/ActionReview.vue: "An app", "untitled"), never to "undefined".
///
/// Every sentence here is copy: PebbleDesign's banned-word check scans this file.
public enum CardWords {
    /// The card's heading as Pebble writes it: the command, the file, "Run isolated tests", "Use Safari".
    public static func heading(kind: CardKind, payload p: JSONValue) -> String {
        switch kind {
        case .edit: return text(p["path"]) ?? "A file in your project"
        case .tests: return isCheck(p) ? "Run an ad hoc check" : "Run isolated tests"
        case .command, .shell: return text(p["command"]) ?? "A command"
        case .plugin: return "\(text(p["name"]) ?? "A connector") / \(text(p["tool"]) ?? "a tool")"
        case .git: return "Git \(text(p["operation"]) ?? "change")"
        case .worktree:
            return text(p["operation"]) == "retire_child_worktree" ? "Retire child worktree" : "Allocate child worktree"
        case .install: return "Install dependencies (\(text(p["kind"]) ?? "lockfile"))"
        case .file: return text(p["path"]) ?? "A file on your Mac"
        case .screen: return screenHeading(p["review"])
        case .screenGrant: return "Use \(text(p["app"]) ?? "an app")"
        case .url: return "Open \(text(p["url"]) ?? "a web address")"
        case .screenRaise: return "Bring \(text(p["app"]) ?? "an app") forward"
        case .appAction: return text(p["summary"]) ?? "Use \(text(p["app"]) ?? "an app")"
        case .browserGrant:
            let names = siteNames(p["sites"])
            return "Use \(names.isEmpty ? "these sites" : names)"
        case .app: return appHeading(p)
        default:
            // A kind this version does not know: Pebble's own summary when it gave one, else its pending state.
            return text(p["summary"]) ?? "Needs your review"
        }
    }

    /// A short title: what approving does, with its subject ("Run npm test", "Change App.vue"). Face ID shows it
    /// after "Approve: ".
    public static func title(kind: CardKind, payload p: JSONValue) -> String {
        let title: String
        switch kind {
        case .edit:
            let name = fileName(text(p["path"])) ?? "a file"
            title = (truthy(p["baseline"]) ? "Change " : "Create ") + name
        case .command, .shell:
            title = "Run " + (firstLine(text(p["command"])) ?? "a command")
        case .plugin:
            title = "Call " + heading(kind: kind, payload: p)
        case .file:
            title = (text(p["op"]) == "edit" ? "Edit " : "Write ") + (fileName(text(p["path"])) ?? "a file")
        default:
            title = heading(kind: kind, payload: p)
        }
        return clamp(title, 120)
    }

    /// The exact thing to approve, when there is one: the command, the path, the address, the sites.
    public static func detail(kind: CardKind, payload p: JSONValue) -> String? {
        let value: String?
        switch kind {
        case .edit, .file: value = text(p["path"])
        case .command, .shell: value = text(p["command"])
        case .tests:
            value = text(p["recipe"]) ?? text(p["plan"]?["recipe"])
        case .plugin:
            value = p["arguments"].flatMap { try? FrameCodec.jsonText($0) }
        case .git: value = text(p["summary"]) ?? text(p["message"])
        case .worktree: value = text(p["path"])
        case .install: value = text(p["summary"])
        case .screen:
            let review = p["review"]
            value = text(review?["text"]) ?? text(review?["element"]?["label"])
        case .screenGrant, .screenRaise: value = text(p["title"])
        case .url: value = text(p["url"])
        case .appAction: value = text(p["args"]?["text"]) ?? text(p["summary"])
        case .browserGrant:
            let sites = (p["sites"]?.array ?? []).compactMap { text($0) }
            value = sites.isEmpty ? text(p["url"]) : sites.joined(separator: "\n")
        case .app: value = text(p["document"]) ?? text(p["name"])
        default: value = nil
        }
        return value.map { clamp($0, 8000) }
    }

    /// Pebble's one plain sentence on what approving changes and whether it can be undone (App.vue `actionLead`),
    /// word for word. nil for a kind Pebble has no sentence for.
    public static func summary(kind: CardKind, payload p: JSONValue) -> String? {
        switch kind {
        case .edit:
            let lead =
                truthy(p["baseline"])
                ? "Changes this file in your project. You can undo it afterwards."
                : "Creates this file in your project. You can undo it afterwards."
            if let scope = p["scope_review"]?.string { return "\(scope) \(lead)" }
            return lead
        case .tests:
            if isCheck(p) && truthy(p["check_run"]) {
                return
                    "Runs the project's tests, then Pebble's own check alone, each in a temporary copy. Your project files don't change."
            }
            return isCheck(p)
                ? "Runs Pebble's own check, added to a temporary copy for this run only. Your project files don't change."
                : "Runs the project's tests in a temporary copy. Your project files don't change."
        case .command:
            return truthy(p["writable"])
                ? "Runs this command in your project, where it can change files. Pebble can't undo a command."
                : "Runs this command in your project without changing files."
        case .plugin:
            return
                "Calls a tool of a connector you turned on. What it changes depends on that service; Pebble can't undo it."
        case .git:
            return text(p["operation"]) == "undo"
                ? "Undoes an earlier Git change."
                : "Runs this Git change in your project. You can propose an undo afterwards, as a new reviewed plan."
        case .worktree:
            return text(p["operation"]) == "retire_child_worktree"
                ? "Removes an agent's separate working copy of the project."
                : "Creates a separate working copy of your project for an agent. Your project stays as it is."
        case .install:
            return "Installs the project's locked dependencies into a folder Pebble manages, outside your project."
        case .app:
            if truthy(p["document"]) {
                let document = text(p["document"]) ?? ""
                let background = truthy(p["background"]) ? ", without bringing it to the front" : ""
                return "Opens \(document) in this app on your Mac\(background). Pebble won't control what happens inside it."
            }
            return truthy(p["background"])
                ? "Opens this app in the background on your Mac, without bringing it to the front. Pebble won't control what happens inside it."
                : "Opens this app on your Mac. Pebble won't control what happens inside it."
        case .shell:
            return "Runs this command in Pebble's sandbox on your Mac."
        case .file:
            return "Writes this file on your Mac. Pebble keeps a copy first, so you can undo it."
        case .screen:
            let review = p["review"]
            let reasons = (review?["reasons"]?.array ?? []).compactMap(\.string)
            if reasons.contains(where: sendingReasons.contains) {
                return "Does this in the app window you shared. It may send, submit, save, delete or buy, and Pebble can't undo it."
            }
            let action = review?["action"]?.string ?? ""
            if startsWithWord(action, ["type", "type_text", "key"]) || review?["text"]?.string != nil {
                return "Types this in the app window you shared. Pebble can't undo typing."
            }
            return "Presses this in the app window you shared. Pebble can't undo a press."
        case .screenGrant:
            if truthy(p["file_panel"]) {
                return
                    "This window is a file panel: it shows one of your folders, and Pebble would read the names of the files listed there. Allow it only if that is what you want."
            }
            let screenshots = truthy(p["screenshots"])
            return "Lets Pebble see and use this one window in this conversation, for up to 15 minutes"
                + (screenshots ? ", with pictures of it when needed. " : ". ")
                + (truthy(p["full_access"])
                    ? "In Full access Pebble runs the presses your messages ask for; anything that may spend money still asks."
                    : "Most presses still ask you first.")
                + (screenshots
                    ? " If macOS asks whether Pebble may bypass its window picker, choose Allow for the pictures." : "")
        case .url:
            return "Opens this address in your browser. Pebble can't see the page, so it can't confirm what happens there."
        case .screenRaise:
            return "Brings this window to the front so Pebble can read it. macOS may switch to its desktop."
        case .appAction:
            return
                "Asks this app to do one thing through its own scripting. Pebble never sends mail or deletes anything this way."
        case .browserGrant:
            if text(p["route"]) == "window" {
                let browser = text(p["browser_name"]) ?? "browser"
                return
                    "Opens these sites in a new \(browser) window that Pebble reads and uses in this conversation, for up to 15 minutes. Sending, buying or deleting still asks you."
            }
            return
                "Lets Pebble use these sites in its own tab in your browser in this conversation, for up to 15 minutes. Sending, buying or deleting still asks you."
        default:
            return nil
        }
    }

    /// The approve button's words, as on Pebble's card.
    public static func approveLabel(kind: CardKind, payload p: JSONValue) -> String {
        switch kind {
        case .edit: "Apply edit"
        case .tests: "Run tests"
        case .command, .shell: "Run command"
        case .plugin: "Call plugin"
        case .git: "Run Git plan"
        case .worktree: text(p["operation"]) == "retire_child_worktree" ? "Retire worktree" : "Create worktree"
        case .install: "Install from lockfile"
        case .file: "Write file"
        case .screen, .appAction: "Do it"
        case .screenGrant, .browserGrant: "Allow"
        case .url: "Open link"
        case .screenRaise: "Bring forward"
        case .app: "Open app"
        default: "Allow"
        }
    }

    /// The reject button's words, as on Pebble's card.
    public static let rejectLabel = "Don't allow"

    // MARK: - Pebble's helpers, ported

    /// The classification reasons that make a press look like sending, submitting, saving, deleting or buying.
    static let sendingReasons: Set<String> = [
        "label_commit_word", "form_submit", "transfer", "enter_submits", "newline_submits", "leaves_origin",
    ]

    /// App.vue `screenHeading`: "Press “Send” in Mail".
    static func screenHeading(_ review: JSONValue?) -> String {
        let verb = text(review?["action"]) ?? "act"
        let label = String((review?["element"]?["label"]?.string ?? "").trimmingCharacters(in: .whitespaces).prefix(40))
        let rawTitle = review?["window"]?["title"]?.string ?? ""
        let title = String(windowTitleHead(rawTitle).trimmingCharacters(in: .whitespaces).prefix(40))
        return verb.prefix(1).uppercased() + verb.dropFirst() + (label.isEmpty ? "" : " “\(label)”")
            + " in \(title.isEmpty ? "an app window" : title)"
    }

    /// The part of a window title before " | ", " — ", " – " or " - " (App.vue splits on /\s[|—–-]\s/).
    static func windowTitleHead(_ title: String) -> String {
        let characters = Array(title)
        var index = 0
        while index + 2 < characters.count {
            if characters[index].isWhitespace, "|—–-".contains(characters[index + 1]), characters[index + 2].isWhitespace {
                return String(characters[..<index])
            }
            index += 1
        }
        return title
    }

    /// App.vue `siteNames`: each site's host without "www.", once each, joined by ", ".
    static func siteNames(_ sites: JSONValue?) -> String {
        var seen: [String] = []
        for site in sites?.array ?? [] {
            let raw = text(site) ?? ""
            var name = raw
            if let url = URL(string: raw), url.scheme != nil, let host = url.host(), !host.isEmpty {
                name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            }
            if !name.isEmpty, !seen.contains(name) { seen.append(name) }
        }
        return seen.joined(separator: ", ")
    }

    static func appHeading(_ p: JSONValue) -> String {
        let name = text(p["name"]) ?? "an app"
        if let document = text(p["document"]), let file = document.split(separator: "/").last {
            return "Open \(file) in \(name)"
        }
        return "Open \(name)"
    }

    /// ActionReview.vue `isCheck`: an ad hoc check RunTests added to the isolated copy.
    static func isCheck(_ p: JSONValue) -> Bool {
        p["check"]?.object != nil && p["check"]?["content"]?.string != nil
    }

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

    /// A string field as text: strings as they are, numbers and booleans spelled out, empty or missing as nil.
    static func text(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let string)?: string.isEmpty ? nil : string
        case .int(let number)?: String(number)
        case .double(let number)?: String(number)
        case .bool(let flag)?: flag ? "true" : "false"
        default: nil
        }
    }

    static func fileName(_ path: String?) -> String? {
        guard let path else { return nil }
        let name = path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
        return name.isEmpty ? nil : name
    }

    /// The first line with words in it, marked "…" when more lines follow.
    static func firstLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        return lines.count > 1 ? first + " …" : first
    }

    /// JavaScript's /^(a|b|c)\b/: the text starts with one of the words, followed by its end or a non-word character.
    static func startsWithWord(_ text: String, _ words: [String]) -> Bool {
        words.contains { word in
            guard text.hasPrefix(word) else { return false }
            guard let next = text.dropFirst(word.count).first else { return true }
            return !(next.isASCII && (next.isLetter || next.isNumber) || next == "_")  // \w is ASCII only
        }
    }

    static func clamp(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
