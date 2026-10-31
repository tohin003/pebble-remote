import Foundation
import Observation

/// Words written but not sent yet, kept where they were written, as a messaging app keeps a chat's draft (the person,
/// 2026-10-31: "i want the words to stay saved in the input text section even if the keyboard is closed like in
/// whatsapp"). Closing the keyboard, leaving the conversation, a reconnect or the app closing keeps them; sending clears
/// them.
///
/// The live store keeps a conversation's words and Ask Pebble's in a file on this iPhone, readable only while the phone
/// is unlocked. A new conversation's words last as long as the app does: it isn't a conversation yet. The demo keeps
/// its words in memory, apart from the person's. Forgetting the Mac, or pairing another, deletes them all.
@MainActor
@Observable
public final class UnsentText {
    /// Where words wait.
    public enum Place: Hashable, Sendable {
        /// A conversation on the Mac.
        case chat(ChatID)
        /// A new conversation before its first message (`ConversationDraft.id`).
        case newConversation(String)
        /// The Pebble tab's Ask Pebble field.
        case askPebble

        /// Its name in the file; nil for a place the file doesn't keep.
        var fileKey: String? {
            switch self {
            case .chat(let id): "chat:\(id)"
            case .askPebble: "ask"
            case .newConversation: nil
            }
        }

        init?(fileKey: String) {
            if fileKey == "ask" {
                self = .askPebble
            } else if fileKey.hasPrefix("chat:"), fileKey.count > 5 {
                self = .chat(String(fileKey.dropFirst(5)))
            } else {
                return nil
            }
        }
    }

    private var texts: [Place: String] = [:]
    /// The file the words are kept in; nil keeps them in memory only (the demo, tests, previews).
    @ObservationIgnored private let file: URL?
    @ObservationIgnored private var saving: Task<Void, Never>?

    /// - Parameter file: where to keep them across launches; what it holds already comes back.
    public init(file: URL? = nil) {
        self.file = file
        guard let file, let data = try? Data(contentsOf: file),
            let kept = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        for (key, text) in kept where !text.isEmpty {
            if let place = Place(fileKey: key) { texts[place] = text }
        }
    }

    /// The words waiting there, exactly as written ("" when none). Setting "" clears the place.
    public subscript(place: Place) -> String {
        get { texts[place] ?? "" }
        set {
            guard newValue != texts[place] ?? "" else { return }
            texts[place] = newValue.isEmpty ? nil : newValue
            if place.fileKey != nil { saveSoon() }
        }
    }

    /// Words wait there, beyond spaces and line breaks.
    public func hasWords(_ place: Place) -> Bool {
        !self[place].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Deletes every place's words, from the file too: the Mac is forgotten, or another is paired.
    public func removeAll() {
        texts = [:]
        saveNow()
    }

    /// Writes the file now (the app goes to the background); otherwise it is written a moment after the typing stops.
    public func saveNow() {
        saving?.cancel()
        saving = nil
        guard let file else { return }
        var kept: [String: String] = [:]
        for (place, text) in texts {
            if let key = place.fileKey { kept[key] = text }
        }
        do {
            guard !kept.isEmpty else {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                return
            }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(kept)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: file, options: .atomic)
            #endif
        } catch {
            // Still kept in memory; the next change, or the app going to the background, writes again.
        }
    }

    private func saveSoon() {
        saving?.cancel()
        saving = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// The live store's file: `Application Support/PebbleRemote/unsent.json` in the app's own container.
    public static var standardFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "PebbleRemote", directoryHint: .isDirectory)
            .appending(path: "unsent.json", directoryHint: .notDirectory)
    }
}
