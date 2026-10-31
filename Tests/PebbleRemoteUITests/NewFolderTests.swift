import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// "New Folder" in the folder browser (lane F, proposal v0.6): when the button shows, when the alert's Create is ready
/// and what the alert says, how the new folder joins the list and opens, and how making one comes out.
struct NewFolderTests {
    static let home = "/Users/you"
    static let projects = "/Users/you/Projects"

    static func listing(_ path: String = projects, _ names: [String] = ["pebble-docs", "sketches"]) -> FolderListing {
        FolderListing(
            home: home, path: path, parent: path == home ? nil : (path as NSString).deletingLastPathComponent,
            folders: names.map { FolderEntry(name: $0, path: path + "/" + $0, isProject: false) })
    }

    // MARK: - The button and the alert

    @Test func theButtonShowsWhereTheBridgeMakesFoldersAndTheFoldersListed() {
        #expect(NewFolderControls(isOffered: true, hasListing: true, isBusy: false).showsButton)
        #expect(!NewFolderControls(isOffered: false, hasListing: true, isBusy: false).showsButton)  // an older bridge
        #expect(!NewFolderControls(isOffered: true, hasListing: false, isBusy: false).showsButton)  // no parent yet
        #expect(NewFolderControls(isOffered: true, hasListing: true, isBusy: false).buttonIsEnabled)
        let busy = NewFolderControls(isOffered: true, hasListing: true, isBusy: true)  // choosing or making one
        #expect(busy.showsButton && !busy.buttonIsEnabled)
    }

    @Test func createGoesOnToFaceIDOnlyWithANameTheMacCanTake() {
        let controls = NewFolderControls(isOffered: true, hasListing: true, isBusy: false)
        for name in ["my-app", "  my app  ", "v1.2", "caf\u{E9}", String(repeating: "x", count: 255)] {
            #expect(controls.problem(typed: name) == nil, "\(name.prefix(10))")
        }
        for name in ["", "   ", ".", "..", ".hidden", "a/b", "a:b", "a\nb", String(repeating: "x", count: 256)] {
            #expect(controls.problem(typed: name) != nil, "\(name.prefix(10).debugDescription)")
        }
        // What Create says when it is tapped with a name that can't go on: the bridge's words.
        #expect(controls.problem(typed: "") == StoreWords.folderNameEmpty)
        #expect(controls.problem(typed: "a/b") == StoreWords.folderNameSeparator)
        #expect(controls.problem(typed: String(repeating: "x", count: 256)) == StoreWords.folderNameTooLong)
    }

    @Test func theAlertSaysWhereTheFolderGoesWhyANameFailsOrWhyTheLastTryDid() {
        let controls = NewFolderControls(isOffered: true, hasListing: true, isBusy: false)
        let where_ = AppCopy.ConnectProject.newFolderMessage(in: "Projects")
        #expect(where_ == "Pebble makes it on your Mac, in Projects. Creating it asks for Face ID.")
        // Nothing typed yet, or a good name: where it goes and that it asks for Face ID.
        #expect(controls.message(typed: "", failure: nil, parent: "Projects") == where_)
        #expect(controls.message(typed: "my-app", failure: nil, parent: "Projects") == where_)
        // A name that can't work: the bridge's words, as it is typed.
        #expect(controls.message(typed: "a/b", failure: nil, parent: "Projects") == StoreWords.folderNameSeparator)
        #expect(controls.message(typed: ".git", failure: nil, parent: "Projects") == StoreWords.folderNameDot)
        // The Mac refused the last try: its words come first, until the name changes.
        let taken = "A folder with that name is already there."
        #expect(controls.message(typed: "my-app", failure: taken, parent: "Projects") == taken)
    }

    @Test func theCopyIsTheFilesAppsAndSaysFaceID() {
        #expect(AppCopy.ConnectProject.newFolder == "New Folder")
        #expect(AppCopy.ConnectProject.createFolder == "Create" && AppCopy.Common.cancel == "Cancel")
        #expect(AppCopy.ConnectProject.folderNamePrompt == "Folder name")
        #expect(AppCopy.ConnectProject.newFolderHint.contains("Face ID"))
        #expect(AppCopy.ConnectProject.folderMade("my-app") == "my-app is made on your Mac.")
    }

    // MARK: - The new folder opens

    @Test func theNewFolderJoinsTheListWhereItSortsAndOnlyOnce() {
        let made = FolderEntry(name: "my-ideas", path: Self.projects + "/my-ideas", isProject: false)
        let after = Self.listing().adding(made)
        #expect(after.folders.map(\.name) == ["my-ideas", "pebble-docs", "sketches"])
        #expect(after.adding(made) == after)  // a second time changes nothing
        let last = Self.listing().adding(FolderEntry(name: "zeta", path: Self.projects + "/zeta"))
        #expect(last.folders.map(\.name) == ["pebble-docs", "sketches", "zeta"])
        let empty = Self.listing(Self.projects, []).adding(made)
        #expect(empty.folders == [made])
        #expect(empty.path == Self.projects && empty.parent == Self.home)  // the rest of the listing is as it was
    }

    @Test func aFolderJustMadeOpensEmptyWithItsParentAboveItSoConnectIsReady() {
        let parent = Self.listing()
        let made = FolderEntry(name: "my-ideas", path: Self.projects + "/my-ideas", isProject: false)
        let opened = parent.opening(made)
        #expect(opened.path == made.path && opened.parent == Self.projects && opened.home == Self.home)
        #expect(opened.folders.isEmpty && !opened.isHome && opened.name == "my-ideas")  // "Connect this folder" is ready
        // In the home folder too: its listing's parent is nil, the new folder's is home.
        let homeMade = Self.listing(Self.home, ["Projects"]).opening(FolderEntry(name: "New", path: Self.home + "/New"))
        #expect(homeMade.parent == Self.home && !homeMade.isHome)
        // The route carries it, so the screen has the folder before the Mac answers.
        let route = FolderRoute(path: made.path, initial: opened)
        #expect(route.initial == opened && route != FolderRoute(path: made.path))
        #expect(FolderRoute(path: made.path) == FolderRoute(path: made.path, initial: nil))
    }

    // MARK: - How making one comes out

    @MainActor
    private func demoStore() async -> RemoteStore {
        let client = DemoClient(pace: 0, autoplay: false, now: { Date(timeIntervalSince1970: 1_761_759_000) })
        let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(), isDemo: true)
        store.start()
        _ = await waitUntil { store.pebble != nil }
        return store
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @MainActor
    @Test func aMadeFolderComesBackAsTheEntryTheScreenOpens() async {
        let store = await demoStore()
        let result = await store.makeFolder(named: "  my-ideas ", in: Self.projects)
        let expected = FolderEntry(name: "my-ideas", path: Self.projects + "/my-ideas", isProject: false)
        #expect(result == .made(expected))
        #expect(store.notice == nil)
        #expect(store.isRecentlyMade(expected.path))  // so connecting it asks for no second Face ID
    }

    @MainActor
    @Test func aRefusalComesBackInTheMacsWordsAndLeavesNoNoticeBehind() async {
        let store = await demoStore()
        #expect(
            await store.makeFolder(named: "pebble-web", in: Self.projects)
                == .refused("A folder with that name is already there."))
        #expect(store.notice == nil)  // taken, to show inside the sheet
        #expect(
            await store.makeFolder(named: "x", in: "/etc")
                == .refused("Pebble Remote shows folders inside your home folder only."))
        #expect(await store.makeFolder(named: ".hidden", in: Self.projects) == .refused(StoreWords.folderNameDot))
        #expect(await store.makeFolder(named: "  ", in: Self.projects) == .refused(StoreWords.folderNameEmpty))
        #expect(store.notice == nil)
    }

    @MainActor
    @Test func aMacThatCantBeReachedIsSaidInPlainWords() async {
        let store = RemoteStore(client: DemoClient(pace: 0, autoplay: false))  // never connected
        #expect(await store.makeFolder(named: "my-app", in: Self.projects) == .refused(StoreWords.notConnected))
        #expect(store.notice == nil)
    }

    @MainActor
    @Test func cancellingFaceIDSaysNothing() async {
        let store = RemoteStore(client: FaceIDCancellingClient())
        #expect(await store.makeFolder(named: "my-app", in: Self.projects) == .cancelled)
        #expect(store.notice == nil && !store.isRecentlyMade(Self.projects + "/my-app"))
    }
}

/// A client whose Face ID the person always cancels.
nonisolated final class FaceIDCancellingClient: RemoteClient {
    let updates = AsyncStream<ClientUpdate> { _ in }

    func connect(to mac: PairedMac) async {}
    func disconnect() async {}
    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue { .bool(true) }

    func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        throw RemoteCallError.cancelledByPerson
    }

    func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac {
        throw RemoteCallError.notImplemented("pair")
    }
}
