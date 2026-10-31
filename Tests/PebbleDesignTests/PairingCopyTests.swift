import Testing

@testable import PebbleDesign

/// Lane X, contract X-1: the words on the screen that shows the code and on the one that follows a pairing the Mac did
/// not confirm. (`BannedWordTests` also scans every literal in this module.)
struct PairingCopyTests {
    @Test func theScreenSaysWhatToDoWithTheCode() {
        // The sentence the person's brief asks for, word for word.
        #expect(AppCopy.Pairing.codePrompt == "Check that your Mac shows the same code, then confirm on your Mac.")
        #expect(AppCopy.Pairing.codeTitle == "Confirm on Your Mac")
        // A code that differs is the whole point of the check: the screen says what to do then.
        #expect(AppCopy.Pairing.codeMismatch.contains("different") && AppCopy.Pairing.codeMismatch.contains("Cancel"))
        #expect(AppCopy.Pairing.codeTimeLimit.contains("2 minutes"))
    }

    @Test func aPairingTheMacDidNotConfirmSaysWhyAndWhatToDo() {
        let words = AppCopy.Pairing.notConfirmed
        #expect(words.contains("cancelled") && words.contains("2 minutes"))  // the two things the Mac's `bye` can mean
        #expect(words.contains("new pairing link"))  // the pairing code is spent: the next step
        #expect(AppCopy.Errors.forCode("bad_code") == words)
        #expect(AppCopy.Errors.forCode("not_confirmed") == words)
    }

    @Test func theHowToSaysTheMacWillAskForTheCode() {
        #expect(AppCopy.Pairing.howTo.contains("confirm"))
    }

    @Test func noneOfItIsJargon() {
        let all = [
            AppCopy.Pairing.howTo, AppCopy.Pairing.codeTitle, AppCopy.Pairing.codePrompt, AppCopy.Pairing.codeMismatch,
            AppCopy.Pairing.codeWaiting, AppCopy.Pairing.codeTimeLimit, AppCopy.Pairing.codeLabel,
            AppCopy.Pairing.notConfirmed,
        ]
        for text in all {
            #expect(BannedWords.isClean(text), "\(text)")
            #expect(text == text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
