import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// Lane Z, item 3: the composer's "/" commands, by the rules of Pebble's window (slashCommands.ts). The list never offers
// the words that settle a goal (the lead, 02:55); typed by hand, they go to Pebble like any message.

struct SlashInputTests {
    @Test func aSlashAndANameAreTheNameStage() {
        #expect(SlashInput.parse("/") == SlashInput(name: "", stage: .name))
        #expect(SlashInput.parse("/STA") == SlashInput(name: "sta", stage: .name))
        #expect(SlashInput.parse("/re-sume_2") == SlashInput(name: "re-sume_2", stage: .name))
    }

    @Test func aSpaceAfterTheNameStartsTheArguments() {
        #expect(SlashInput.parse("/memory ") == SlashInput(name: "memory", stage: .argument))
        #expect(SlashInput.parse("/memory sta") == SlashInput(name: "memory", partial: "sta", stage: .argument))
        #expect(SlashInput.parse("/criteria add ") == SlashInput(name: "criteria", args: ["add"], stage: .argument))
        #expect(
            SlashInput.parse("/goal \"Ship the") == SlashInput(name: "goal", partial: "\"Ship the", stage: .argument))
        #expect(
            SlashInput.parse("/goal \"Ship it\" ") == SlashInput(name: "goal", args: ["\"Ship it\""], stage: .argument))
    }

    @Test func whatIsNotOneCommandLineIsNotParsed() {
        #expect(SlashInput.parse("hello /status") == nil)
        #expect(SlashInput.parse("/status\nmore") == nil)
        #expect(SlashInput.parse("/ status") == nil)
        #expect(SlashInput.parse("/goal!") == nil)
        #expect(SlashInput.parse("/" + String(repeating: "a", count: 33)) == nil)
        #expect(SlashInput.parse("/café") == nil)
    }
}

struct SlashCommandsTests {
    static let catalogue = PebbleCommand.catalogue(DemoCommands.catalogueJSON)

    @Test func theCatalogueIsPebblesTwentyEight() {
        #expect(Self.catalogue.count == 28)
        #expect(Self.catalogue.first == PebbleCommand(name: "jobs", description: "List this conversation's schedules and waiting notifications."))
    }

    @Test func aCatalogueKeepsOnlyWhatPebblesWindowAccepts() {
        let json: JSONValue = [
            ["name": "status", "arguments": "", "description": "Show it."],
            ["name": "status", "arguments": "", "description": "Twice."],
            ["name": "Bad", "arguments": "", "description": "Capital."],
            ["name": "9lives", "arguments": "", "description": "Digit first."],
            ["name": "long", "arguments": .string(String(repeating: "x", count: 161)), "description": "Long arguments."],
            ["name": "wordy", "arguments": "", "description": .string(String(repeating: "x", count: 401))],
            ["name": "plan", "description": "No arguments field."],
            ["name": "help", "arguments": "", "description": "List them."],
        ]
        #expect(PebbleCommand.catalogue(json).map(\.name) == ["status", "help"])
        #expect(PebbleCommand.catalogue(["not": "a list"]).isEmpty)
    }

    @Test func theWindowsFirstRowsComeFirst() {
        let names = SlashCommands.ordered(Self.catalogue).map(\.name)
        #expect(Array(names.prefix(5)) == ["goal", "status", "compact", "memory", "skill"])
        #expect(names.count == 28 && Set(names).count == 28)
        #expect(names[5] == "jobs")
    }

    @Test func filteringRanksTheNameBeforeTheDescription() {
        let ordered = SlashCommands.ordered(Self.catalogue)
        // The name first, then the descriptions that mention it, in the list's order.
        #expect(SlashCommands.filter(ordered, query: "goal").map(\.name) == ["goal", "criteria", "blockers"])
        #expect(SlashCommands.filter(ordered, query: "RE").first?.name == "resume")
        #expect(SlashCommands.filter(ordered, query: "checks").map(\.name) == ["hooks"])
        #expect(SlashCommands.filter(ordered, query: "").count == 28)
        #expect(SlashCommands.filter(ordered, query: "zzz").isEmpty)
    }

    @Test func choosingFillsTheNameAndASpace() {
        #expect(SlashCommands.fill(PebbleCommand(name: "status", description: "")) == "/status ")
        let input = SlashInput(name: "memory", partial: "st", stage: .argument)
        #expect(SlashCommands.complete(input, with: "status") == "/memory status ")
    }

    @Test func argumentWordsAreTheWindowsWithoutTheOnesThatSettleAGoal() {
        #expect(SlashCommands.options(for: SlashInput(name: "memory", stage: .argument)) == ["status", "candidates", "maintain"])
        #expect(SlashCommands.options(for: SlashInput(name: "memory", partial: "ca", stage: .argument)) == ["candidates"])
        #expect(SlashCommands.options(for: SlashInput(name: "goal", stage: .argument)) == ["pause", "resume"])
        #expect(SlashCommands.options(for: SlashInput(name: "goal", partial: "d", stage: .argument)).isEmpty)
        #expect(SlashCommands.options(for: SlashInput(name: "criteria", stage: .argument)) == ["add"])
        #expect(SlashCommands.options(for: SlashInput(name: "criteria", args: ["add"], stage: .argument)) == ["--evidence"])
        #expect(SlashCommands.options(for: SlashInput(name: "criteria", args: ["check"], stage: .argument)).isEmpty)
        #expect(SlashCommands.options(for: SlashInput(name: "status", stage: .argument)).isEmpty)
        #expect(SlashCommands.options(for: SlashInput(name: "memory", stage: .name)).isEmpty)
    }

    @Test func aCommandThatNeedsAnArgumentSaysSo() {
        let byName = Dictionary(uniqueKeysWithValues: Self.catalogue.map { ($0.name, $0) })
        #expect(byName["steer"]?.needsArguments == true && byName["agent"]?.needsArguments == true)
        #expect(byName["resume"]?.needsArguments == false && byName["status"]?.needsArguments == false)
    }

    /// The list shows Pebble's arguments less the alternatives that settle a goal.
    @Test func theArgumentsShownLeaveOutWhatSettlesAGoal() {
        let byName = Dictionary(uniqueKeysWithValues: Self.catalogue.map { ($0.name, $0) })
        #expect(byName["goal"].map(SlashCommands.shownArguments) == "[\"title\"|pause|resume]")
        #expect(byName["criteria"].map(SlashCommands.shownArguments) == "[add [--evidence] \"text\"]")
        #expect(byName["memory"].map(SlashCommands.shownArguments) == "[status|candidates|maintain]")
        #expect(byName["resume"].map(SlashCommands.shownArguments) == "[run-id] [--steps N] [--seconds N]")
        #expect(byName["steer"].map(SlashCommands.shownArguments) == "text")
    }
}

@MainActor
private func slashStore(
    bridge: BridgeInfo = .test(methods: ["state", "get_chat", "send", "new_chat", "command_catalogue"])
) async -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, _ in
        switch method {
        case "state": return Fixture.stateJSON()
        case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
        case "command_catalogue": return DemoCommands.catalogueJSON
        case "new_chat": return Fixture.chatDetail("c2", title: "")
        default: return ["message_id": "m9", "command": true]
        }
    }
    let store = RemoteStore(client: fake)
    fake.push(.status(ConnectionStatus(phase: .connected, route: .lan, roundTrip: 6)))
    fake.push(.welcome(bridge))
    _ = await eventually { store.pebble != nil }
    return (store, fake)
}

@MainActor
@Test func theCatalogueIsReadFromPebble() async throws {
    let (store, fake) = await slashStore()
    let commands = try await store.commandCatalogue()
    #expect(commands.count == 28 && commands.contains { $0.name == "memory" })
    #expect(fake.calls("command_catalogue").count == 1)
}

@MainActor
@Test func aBridgeWithoutTheCatalogueIsNotAsked() async throws {
    let (store, fake) = await slashStore(bridge: .test(methods: ["state", "get_chat", "send"]))
    await #expect(throws: RemoteCallError.self) { try await store.commandCatalogue() }
    #expect(fake.calls("command_catalogue").isEmpty)
    #expect(store.notice == nil)
}

/// The lead (02:55): the phone adds nothing when the person types a goal-settling command by hand; Pebble answers it.
@MainActor
@Test func aCommandTypedByHandGoesToPebbleAsTyped() async throws {
    let (store, fake) = await slashStore()
    try await store.send("/goal done", in: "c1")
    #expect(fake.calls("send").last?.params["text"] == "/goal done")
    #expect(store.notice == nil)
}

@MainActor
@Test func theDemoAnswersItsCommandsAndRefusesUnknownOnes() async throws {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    await client.connect(to: DemoClient.pairedMac(at: Fixture.t0))
    let catalogue = PebbleCommand.catalogue(try await client.call("command_catalogue", [:]))
    #expect(catalogue.count == 28)
    let sent = try await client.call("send", ["id": .string(DemoData.commitsChat), "text": "/memory"])
    #expect(sent["command"] == true)
    await #expect(throws: RemoteCallError.self) {
        try await client.call("send", ["id": .string(DemoData.commitsChat), "text": "/model"])
    }
    #expect(DemoCommands.reply("/help", memory: DemoMemory(now: Fixture.t0)).hasPrefix("Commands you can type:\n\n- /jobs"))
}

/// The demo's catalogue is Pebble's, word for word (runtime_commands.py CATALOGUE), when `PEBBLE_CHECKOUT` names
/// Pebble's checkout.
@Test func theDemosCatalogueIsPebbles() throws {
    let checkout = ProcessInfo.processInfo.environment["PEBBLE_CHECKOUT"] ?? ""
    guard !checkout.isEmpty,
          let source = try? String(contentsOfFile: checkout + "/backend/pebble/runtime_commands.py", encoding: .utf8)
    else { return }
    let start = try #require(source.range(of: "CATALOGUE = ["))
    let end = try #require(source.range(of: "\n]\n", range: start.upperBound..<source.endIndex))
    let catalogue = String(source[start.upperBound..<end.lowerBound]).replacingOccurrences(of: "\\'", with: "'")
    let entries = catalogue.split(separator: "\n").filter { $0.contains("name") }
    #expect(entries.count == DemoCommands.catalogue.count)
    for (entry, command) in zip(entries, DemoCommands.catalogue) {
        #expect(entry.contains("'\(command.name)'") || entry.contains("\"\(command.name)\""), "\(command.name)")
        #expect(entry.contains(command.description), "\(command.name): \(command.description)")
        #expect(entry.contains("'\(command.arguments)'") || entry.contains("\"\(command.arguments)\""), "\(command.name)")
    }
}
