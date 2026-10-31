import Foundation
import Testing

@testable import PebbleDesign

// Lane N's words: the Chats tab as Pebble's sidebar, a new conversation, the composer's "+" menu and its dialogs, and
// "Connect a project". The Mac's own words are compared with Pebble's sources; the phone's own lines are checked here.

extension PebbleParityTests {
    /// The sidebar, the "+" menu and its two dialogs say what Pebble's window says (App.vue).
    @Test func sidebarAndComposerWordsAreWordForWord() throws {
        let app = Self.collapse(try Self.read("src/App.vue"))
        for text in [
            AppCopy.Chats.newConversation, AppCopy.Sidebar.companion, AppCopy.Sidebar.connectProject,
            AppCopy.AddContext.title, AppCopy.AddContext.terminalCommand, AppCopy.AddContext.attachFile,
            AppCopy.AddContext.readWebSource, AppCopy.TerminalCommand.title, AppCopy.TerminalCommand.placeholder,
            AppCopy.TerminalCommand.network, AppCopy.TerminalCommand.note, AppCopy.TerminalCommand.review,
            AppCopy.WebSource.title, AppCopy.WebSource.intro, AppCopy.WebSource.field, AppCopy.WebSource.placeholder,
            AppCopy.WebSource.note, AppCopy.WebSource.attach, AppCopy.WebSource.reading, AppCopy.ConnectProject.connected,
            AppCopy.Draft.welcome, AppCopy.Draft.welcomeInProject,
        ] {
            #expect(app.contains(text), "App.vue: \(text)")
        }
        // Pebble's sentences that hold a name, around the name.
        #expect(app.contains("'New conversation in ' + p"))
        #expect(AppCopy.Sidebar.newConversation(in: "pebble-web") == "New conversation in pebble-web")
        #expect(
            app.contains(
                #"Run one command in {{ projectName || "a connected project" }}. Review the exact command and access before execution."#
            ))
        #expect(
            AppCopy.TerminalCommand.intro(nil)
                == "Run one command in a connected project. Review the exact command and access before execution.")
        #expect(app.contains("`I'm here to help you explore, fix, and build in ${projectName}.`"))
        #expect(AppCopy.Draft.projectDescription("pebble-web") == "I'm here to help you explore, fix, and build in pebble-web.")
        let companion = AppCopy.Draft.companionDescription.replacingOccurrences(of: "\n", with: #"\n"#)
        #expect(app.contains("\"\(companion)\""))
    }

    /// The refusals the phone shows before asking Pebble are Pebble's own (policy.py, coding_api.py, app.py).
    @Test func pebblesRefusalsAreWordForWord() throws {
        #expect(Self.collapse(try Self.read("backend/pebble/policy.py")).contains(AppCopy.ConnectProject.homeRefused))
        #expect(Self.collapse(try Self.read("backend/pebble/coding_api.py")).contains(AppCopy.TerminalCommand.needsProject))
        #expect(Self.collapse(try Self.read("backend/pebble/app.py")).contains(AppCopy.TerminalCommand.whileWorking))
    }
}

/// The phone's own words around Pebble's.
struct SidebarCopyTests {
    /// Every entry point that starts a conversation is named as the Mac names it (R6: "the same names as the Mac").
    @Test func entryPointsAreNamedNewConversation() {
        #expect(AppCopy.Chats.newConversation == "New conversation")
        #expect(AppCopy.Draft.title == AppCopy.Chats.newConversation)
        #expect(AppCopy.Home.startConversation.localizedCaseInsensitiveContains("new conversation"))
        #expect(AppCopy.AddContext.connectProject == AppCopy.Sidebar.connectProject)
    }

    /// A web page waiting for the next message reads as Pebble's chip does (App.vue `sourceLabel`).
    @Test func aWebPagesChipNamesItsSite() {
        #expect(AppCopy.WebSource.chip("https://www.docs.example.com/guide") == "Read: docs.example.com/guide")
        #expect(AppCopy.WebSource.chip("https://example.com/") == "Read: example.com")
        #expect(
            AppCopy.WebSource.chip("https://example.com/a/very/long/path/that/keeps/going")
                == "Read: example.com/a/very/long/path/that/k\u{2026}")
        #expect(AppCopy.WebSource.chip("notes.txt") == "notes.txt")
    }

    /// Where a new conversation starts reads the same in the where control and for VoiceOver.
    @Test func placesReadAsPlaces() {
        #expect(AppCopy.Draft.startsIn(AppCopy.Sidebar.companion) == "In Companion")
        #expect(AppCopy.Sidebar.newConversation(in: AppCopy.Sidebar.companion) == "New conversation in Companion")
        #expect(BannedWords.isClean(AppCopy.Draft.newFolderNote) && BannedWords.isClean(AppCopy.Place.startsNewConversation))
    }
}
