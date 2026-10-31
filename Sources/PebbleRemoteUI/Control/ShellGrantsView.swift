import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Settings › Permissions › Pebble's Shell › Websites and Folders (AdvancedSettings.vue, "PEBBLE'S SHELL"): the places
/// Pebble never reads or writes, then each website and folder Pebble may use without asking, "always allowed" or
/// "allowed until Pebble quits". Remove (a button and a swipe) asks for Face ID, as the bridge does for every change to
/// these grants, and waits while a task runs, as the Mac's does. Nothing is removed without it.
struct ShellGrantsView: View {
    @Environment(RemoteStore.self) private var store
    @State private var grants: [ShellGrant]?
    @State private var removing: String?

    var body: some View {
        List {
            Section {
                ForEach(grants ?? []) { grant in
                    HStack {
                        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                            Label {
                                Text(verbatim: grant.value)
                            } icon: {
                                Image(systemName: grant.kind == .site ? "globe" : "folder")
                                    .foregroundStyle(PebbleColor.accent)
                            }
                            Text(AppCopy.ShellAccess.line(website: grant.kind == .site, always: grant.always))
                                .font(PebbleFont.meta)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer()
                        if removing == grant.id {
                            ProgressView()
                        } else {
                            Button {
                                remove(grant)
                            } label: {
                                Text(AppCopy.ShellAccess.remove)
                                    .tapTarget()
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canRemove)
                            .accessibilityLabel(AppCopy.ShellAccess.removeLabel(grant.value))
                            .accessibilityHint(AppCopy.FaceID.asksFirst)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if canRemove {
                            Button(AppCopy.ShellAccess.remove, systemImage: "minus.circle") { remove(grant) }
                        }
                    }
                }
                if let grants, grants.isEmpty {
                    Text(AppCopy.ShellAccess.empty)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(AppCopy.ShellAccess.section)
            } footer: {
                VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                    Text(AppCopy.ShellAccess.protectedPlaces)
                    if grants?.isEmpty == false {
                        Text(AppCopy.ShellAccess.removeNeedsFaceID)
                    }
                    if store.isPebbleWorking {
                        Text(AppCopy.ShellAccess.idleOnly)
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle(AppCopy.ShellAccess.row)
    }

    /// The Mac's Remove waits while a task runs; one removal goes at a time.
    private var canRemove: Bool {
        store.bridgeOffers("shell_grant_remove") && !store.isPebbleWorking && removing == nil
    }

    private func load() async {
        if let read = await store.attempt({ try await store.shellGrants() }) {
            grants = read
        }
    }

    private func remove(_ grant: ShellGrant) {
        guard canRemove else { return }
        removing = grant.id
        Task {
            if let left = await store.attempt({ try await store.removeShellGrant(grant) }) {
                grants = left
            }
            removing = nil
        }
    }
}
