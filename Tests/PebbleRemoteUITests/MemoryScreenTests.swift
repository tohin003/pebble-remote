import PebbleDesign
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Lane Z, item 4: a contested memory's decision says exactly what it forgets before the person confirms it.
struct MemoryScreenTests {
    static let contest = ContestedMemory(
        record: .init(memoryID: "m2", kind: "profile", content: "Write in British spelling."),
        counterparts: [.init(memoryID: "m3", kind: "profile", content: "Write in American spelling.")])

    @Test func keepThisForgetsTheOthersAndSaysSo() {
        let pending = PendingDecision(contest: Self.contest, decision: .keep)
        #expect(pending.forgets)
        #expect(pending.confirmLabel == "Keep this and forget 1 memory")
        #expect(pending.confirmation.contains("Write in American spelling."))
        #expect(!pending.confirmation.contains("\u{2022} Your preferences \u{00B7} Write in British spelling."))
    }

    @Test func removeThisForgetsItselfAndKeepBothForgetsNothing() {
        let remove = PendingDecision(contest: Self.contest, decision: .reject)
        #expect(remove.forgets && remove.confirmLabel == "Forget this memory")
        #expect(remove.confirmation.hasSuffix(AppCopy.Memories.confirmation(
            "reject", summary: "", forgets: [], counterparts: 1).components(separatedBy: "\n\n").last ?? "x"))
        let both = PendingDecision(contest: Self.contest, decision: .keepBoth)
        #expect(!both.forgets && both.confirmLabel == "Keep both")
        #expect(both.id == "m2/keep_both")
    }
}
