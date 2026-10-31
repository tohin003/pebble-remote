import PebbleDesign
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Lane Z, item 3: what the composer's "/" list shows, and what choosing a line puts in the field (nothing is sent).
struct SlashRowTests {
    static let catalogue = [
        PebbleCommand(name: "jobs", description: "List this conversation's schedules and waiting notifications."),
        PebbleCommand(name: "status", description: "Show how the latest task in this conversation is going."),
        PebbleCommand(name: "compact", arguments: "[run-id]", description: "Make room by archiving older context between steps; no model is asked."),
        PebbleCommand(name: "memory", arguments: "[status|candidates|maintain]", description: "Show memory counts or waiting memories, or check waiting memories now."),
        PebbleCommand(name: "goal", arguments: "[\"title\"|done|pause|resume|abandon]", description: "Start, show or settle this conversation's goal; done needs every criterion met."),
    ]

    static func names(_ rows: [SlashRow]?) -> [String] {
        (rows ?? []).compactMap { row in
            if case .command(let command, _) = row { command.name } else { nil }
        }
    }

    @Test func aSlashListsPebblesCommandsWithTheWindowsFirstRowsFirst() {
        #expect(Self.names(SlashRow.rows(for: "/", catalogue: Self.catalogue, isWorking: false)) == ["goal", "status", "compact", "memory", "jobs"])
        #expect(Self.names(SlashRow.rows(for: "/sta", catalogue: Self.catalogue, isWorking: false)).first == "status")
    }

    @Test func nothingShowsUntilTheCommandsAreReadOrWithoutASlash() {
        #expect(SlashRow.rows(for: "/", catalogue: nil, isWorking: false) == nil)
        #expect(SlashRow.rows(for: "Fix the tests", catalogue: Self.catalogue, isWorking: false) == nil)
        #expect(SlashRow.rows(for: "/status ", catalogue: Self.catalogue, isWorking: false) == nil)
    }

    @Test func noMatchSaysSoInPebblesWords() {
        #expect(SlashRow.rows(for: "/zzz", catalogue: Self.catalogue, isWorking: false) == [.note(AppCopy.Slash.noMatch)])
    }

    @Test func whileATaskWorksTheIdleOnlyCommandsAreDimmedWithTheReason() throws {
        let rows = try #require(SlashRow.rows(for: "/comp", catalogue: Self.catalogue, isWorking: true))
        #expect(rows.first == .command(Self.catalogue[2], unavailable: AppCopy.Slash.idleOnly))
        #expect(rows.first?.chosen(in: "/comp") == nil)
        let resting = try #require(SlashRow.rows(for: "/comp", catalogue: Self.catalogue, isWorking: false))
        #expect(resting.first?.chosen(in: "/comp") == "/compact ")
    }

    @Test func afterACommandItsArgumentWordsShowWithPebblesNotes() {
        #expect(SlashRow.rows(for: "/memory ", catalogue: Self.catalogue, isWorking: false) == [
            .option("status", note: nil), .option("candidates", note: nil), .option("maintain", note: nil),
        ])
        #expect(SlashRow.rows(for: "/goal ", catalogue: Self.catalogue, isWorking: false) == [
            .option("pause", note: AppCopy.Slash.goalTitle), .option("resume", note: AppCopy.Slash.goalTitle),
        ])
        #expect(SlashRow.option("candidates", note: nil).chosen(in: "/memory ca") == "/memory candidates ")
    }

    /// The words that settle a goal are never offered (the lead, 02:55), and typing them by hand adds nothing.
    @Test func goalSettlingWordsAreNeverOffered() {
        #expect(SlashRow.rows(for: "/goal d", catalogue: Self.catalogue, isWorking: false) == nil)
        #expect(SlashRow.rows(for: "/goal done", catalogue: Self.catalogue, isWorking: false) == nil)
        #expect(SlashRow.rows(for: "/criteria ", catalogue: nil, isWorking: false) == [.option("add", note: nil)])
        #expect(SlashRow.rows(for: "/criteria acc", catalogue: nil, isWorking: false) == nil)
    }
}
