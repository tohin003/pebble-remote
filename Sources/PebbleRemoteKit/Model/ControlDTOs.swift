import Foundation
import PebbleProtocol

// Tolerant readers for the Control tab's answers (src/types.ts ModelProfile and State.settings, activity.ts
// ActivityItem, contract 3.8 and C3). Unknown fields are ignored; a record without its id yields nil.

extension PebbleSettings {
    /// From state().settings.
    public init(json: JSONValue) {
        let permissions = json["permissions"]
        var tools: [String: Bool] = [:]
        for (name, value) in permissions?["tools"]?.object ?? [:] { if let on = value.bool { tools[name] = on } }
        var layers: [String: Bool] = [:]
        for (name, value) in json["memory_layers"]?.object ?? [:] { if let on = value.bool { layers[name] = on } }
        self.init(
            theme: json["theme"]?.string ?? "system", reducedMotion: json["reduced_motion"]?.bool ?? false,
            stealth: json["stealth"]?.bool ?? false, memoryEnabled: json["memory_enabled"]?.bool ?? true,
            memoryLayers: layers, mode: permissions?["mode"]?.string.flatMap(PermissionMode.init(rawValue:)) ?? .ask,
            tools: tools, fastReplies: json["fast_replies"]?.string.flatMap(FastReplies.init(rawValue:)),
            companion: json["companion"] ?? .null, gitDecisions: json["git_decisions"] ?? .null)
    }
}

extension ModelChoice {
    /// From one of `model_profiles`. Pebble's account fields (email, keys, connection ids) are never read.
    public init?(profile json: JSONValue) {
        guard let id = json["id"]?.string, !id.isEmpty else { return nil }
        let display = [json["display_name"]?.string, json["model"]?.string, json["name"]?.string]
            .compactMap { $0 }.first { !$0.isEmpty }
        self.init(
            id: id, name: display ?? id, provider: json["provider_name"]?.string ?? json["provider"]?.string,
            isLocal: json["local"]?.bool ?? (json["kind"]?.string == "gguf"),
            efforts: (json["efforts"]?.array ?? []).compactMap(\.string))
    }
}

extension RunActivityItem {
    /// One item of `run_activity`.
    public init?(json: JSONValue) {
        guard let seq = json["seq"]?.int, let label = json["label"]?.string else { return nil }
        let status = json["status"]?.string
        self.init(
            seq: seq, at: json["at"]?.double ?? 0, kind: json["kind"]?.string ?? "note",
            label: PebbleWorld.clean(label, limit: 80) ?? label,
            detail: json["detail"]?.string.flatMap { PebbleWorld.clean($0, limit: 2000) },
            duration: json["duration"]?.double,
            status: status == "running" || status == "failed" ? status! : "done",
            activity: json["activity"]?.string.flatMap(StatusKey.init(rawValue:)),
            view: WorkView(json: json["view"]))
        hasUnreadableView = view == nil && json["view"] != nil && json["view"] != JSONValue.null
    }
}

// Lane G: the work view needs each item's order, status and view (pebble-ui-spec v1).
extension RunActivityItem: WorkItem {
    public var workView: WorkView? { view }
}

extension LiveRunRecord {
    /// From run_get, run_list or a state() run.
    public init?(json: JSONValue) {
        guard let row = RunDTO(json: json) else { return nil }
        let note = PersonNote.filter(row.error)
        self.init(
            id: row.id, chatID: row.chatID, state: row.state, steps: row.steps, elapsed: row.elapsed,
            note: note.isEmpty ? nil : note, created: row.created, updated: row.updated,
            goal: json["goal"]?.string)
    }
}

extension MacDevice {
    /// One of `remote.devices`.
    public init?(json: JSONValue) {
        guard let id = json["device_id"]?.string, !id.isEmpty else { return nil }
        self.init(
            id: id, name: json["name"]?.string ?? "", pairedAt: bridgeDate(json["paired_at"]),
            lastSeen: bridgeDate(json["last_seen"]), isCurrent: json["current"]?.bool ?? false)
    }
}

extension MacScreenshot {
    /// `remote.screenshot`: `{taken_at, displays:[{index, width, height, format, data}]}` with base64 data.
    public init?(json: JSONValue) {
        guard let list = json["displays"]?.array else { return nil }
        let displays: [Display] = list.compactMap { display in
            guard let index = display["index"]?.int, let text = display["data"]?.string,
                let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters)
            else { return nil }
            return Display(
                index: index, width: display["width"]?.int ?? 0, height: display["height"]?.int ?? 0,
                format: display["format"]?.string ?? "jpeg", data: data)
        }
        self.init(takenAt: bridgeDate(json["taken_at"]), displays: displays)
    }
}

extension FolderEntry {
    /// One of `remote.folders`' `folders`: `{name, path, is_project}`.
    public init?(json: JSONValue) {
        guard let path = json["path"]?.string, !path.isEmpty else { return nil }
        let name = json["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? ProjectRef.folderName(path)
        self.init(name: name, path: path, isProject: json["is_project"]?.bool ?? false)
    }
}

extension FolderListing {
    /// `remote.folders` (proposal v0.5): `{home, path, parent, folders: [{name, path, is_project}]}`.
    public init?(json: JSONValue) {
        guard let path = json["path"]?.string, !path.isEmpty, let folders = json["folders"]?.array else { return nil }
        let home = json["home"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? path
        let parent = json["parent"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        self.init(home: home, path: path, parent: parent, folders: folders.compactMap(FolderEntry.init(json:)))
    }
}

/// A time the bridge made: unix milliseconds (contract v0.3), or seconds from an older bridge.
func bridgeDate(_ value: JSONValue?) -> Date? {
    guard let number = value?.double, number.isFinite, number > 0 else { return nil }
    return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
}
