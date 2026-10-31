import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Settings › Skills & connectors › Skills and Connectors: Pebble's skills, connectors and hooks, each with its kind,
/// whether it is on and what it can do, as the Mac's cards say (AdvancedSettings.vue); a row opens its Review, with
/// Enable or Disable. Removing, adding, connector packages and connector sign-in stay on the Mac: one "On your Mac" row
/// says so (lane S, SK-04 to SK-09).
struct ExtensionsView: View {
    @Environment(RemoteStore.self) private var store
    @State private var items: [ExtensionItem]?

    var body: some View {
        List {
            Section {
                ForEach(items ?? []) { item in
                    NavigationLink {
                        ExtensionDetailView(itemID: item.id, items: $items)
                    } label: {
                        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                            Text(verbatim: item.name)
                            Text(
                                AppCopy.Skills.line(
                                    kind: item.kind, enabled: item.enabled, capabilities: item.capabilities)
                            )
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let items, items.isEmpty {
                    Text(AppCopy.Skills.empty)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(AppCopy.Skills.note)
            }
            Section {
                OnYourMacRow(title: AppCopy.Skills.onYourMac)
            } footer: {
                Text(AppCopy.Skills.onYourMacNote)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle(AppCopy.Skills.title)
    }

    private func load() async {
        if let read = await store.attempt({ try await store.extensions() }) {
            items = read
        }
    }
}

/// One skill, connector or hook: whether it is on, with Enable or Disable (Face ID; Pebble refuses while a task runs,
/// and the button waits then, as the Mac's does), then its Review as the Mac's disclosure shows it. A readable file of
/// a skill opens its text.
struct ExtensionDetailView: View {
    let itemID: String
    /// The list it came from, read again after a change.
    @Binding var items: [ExtensionItem]?
    @Environment(RemoteStore.self) private var store
    @State private var isSwitching = false

    private var item: ExtensionItem? { items?.first { $0.id == itemID } }

    var body: some View {
        Form {
            if let item {
                Section {
                    LabeledContent(
                        AppCopy.Skills.noun(item.kind),
                        value: item.enabled ? AppCopy.Skills.enabled : AppCopy.Skills.disabled)
                    if !item.capabilities.isEmpty {
                        Text(verbatim: item.capabilities.joined(separator: ", "))
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                    }
                    if store.bridgeOffers("extension_toggle") {
                        Button {
                            toggle(item)
                        } label: {
                            HStack {
                                Label(
                                    item.enabled ? AppCopy.Skills.disable : AppCopy.Skills.enable,
                                    systemImage: PebbleSymbol.faceID)
                                if isSwitching {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                            .contentShape(.rect)
                        }
                        .disabled(store.isPebbleWorking || isSwitching)
                        .accessibilityHint(AppCopy.FaceID.asksFirst)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                        Text(AppCopy.Skills.startsOff)
                        if store.isPebbleWorking {
                            Text(AppCopy.Learning.idleOnly)
                        }
                    }
                }
                ExtensionReviewSection(item: item)
            }
        }
        .navigationTitle(item?.name ?? AppCopy.Skills.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func toggle(_ item: ExtensionItem) {
        guard !isSwitching else { return }
        isSwitching = true
        Task {
            if await store.attempt({ try await store.setExtension(item, enabled: !item.enabled) }) {
                if let read = await store.attempt({ try await store.extensions() }) { items = read }
            }
            isSwitching = false
        }
    }
}

/// The Mac's "Review skill / connector / hook": its words, a connector's destination, reviewed version, launch files,
/// tools and access, a package's checksum, and a skill's snapshot and files. All of it is Pebble's data, shown
/// literally and selectable.
private struct ExtensionReviewSection: View {
    let item: ExtensionItem

    var body: some View {
        Section {
            if !item.content.isEmpty {
                code(item.content)
            }
            if let connector = item.connector {
                Text(
                    AppCopy.Skills.destination(
                        transport: connector.transport, era: connector.protocolEra, address: connector.address))
                if let version = connector.reviewedVersion {
                    Text(AppCopy.Skills.reviewedVersion(version, protocolVersion: connector.protocolVersion))
                }
                if let files = connector.launchFiles {
                    code(files)
                }
                if let schemas = connector.schemas {
                    code(schemas)
                }
                Text(AppCopy.Skills.access(grantConfigured: connector.holdsGrant))
                if let checksum = connector.packageChecksum {
                    Text(AppCopy.Skills.packageChecksum(checksum))
                }
            }
            if let skill = item.skill {
                Text(AppCopy.Skills.snapshot(skill.snapshot, name: item.name))
                ForEach(skill.files) { file in
                    if file.readable {
                        NavigationLink {
                            SkillTextView(item: item, file: file)
                        } label: {
                            fileLabel(file)
                        }
                        .accessibilityHint(AppCopy.Skills.viewText)
                    } else {
                        fileLabel(file)
                    }
                }
            }
        } header: {
            Text(AppCopy.Skills.review(item.kind))
        }
        .textSelection(.enabled)
    }

    private func code(_ text: String) -> some View {
        Text(verbatim: text)
            .font(PebbleFont.code)
            .foregroundStyle(PebbleColor.text)
    }

    private func fileLabel(_ file: ExtensionItem.SkillFile) -> some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            Text(verbatim: file.path)
            Text(AppCopy.Skills.fileLine(bytes: file.bytes, sha256: file.sha256))
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A skill's reference file as text, from the skill's pinned snapshot, a page at a time ("Load Next Page" adds the
/// next 3,000 characters, as the Mac's does). Scripts are shown as text, never run.
struct SkillTextView: View {
    let item: ExtensionItem
    let file: ExtensionItem.SkillFile
    @Environment(RemoteStore.self) private var store
    @State private var text = ""
    @State private var nextOffset: Int?
    @State private var isLoaded = false
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                if isLoaded {
                    Text(verbatim: text)
                        .font(PebbleFont.code)
                        .foregroundStyle(PebbleColor.text)
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                }
            } footer: {
                Text(AppCopy.Skills.textNote(file.path))
            }
            if let nextOffset {
                Section {
                    Button {
                        Task { await load(from: nextOffset) }
                    } label: {
                        HStack {
                            Text(AppCopy.Skills.loadNextPage)
                            if isLoading {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .contentShape(.rect)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .navigationTitle(file.path.split(separator: "/").last.map(String.init) ?? file.path)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if !isLoaded { await load(from: 0) }
        }
        .refreshable { await load(from: 0) }
    }

    /// A page; a failure leaves the text as it was, and the store's notice says why.
    private func load(from offset: Int) async {
        guard !isLoading else { return }
        isLoading = true
        if let page = await store.attempt({ try await store.skillText(item, file: file.path, from: offset) }) {
            text = offset == 0 ? page.text : text + page.text
            nextOffset = page.nextOffset
        }
        isLoaded = true
        isLoading = false
    }
}
