import Accessibility
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// The Mac's notifications (macOS banners for schedules, and for replies while Pebble is in the background): on or
/// off, what they're about, and how much a banner shows. Each change goes back whole, with the one value changed;
/// quiet hours stay as the Mac has them. Lane S (SG-13): then the Mac's Delivery block, what became of the banners and
/// each schedule's Mute or Unmute (`DeliverySection`).
struct NotificationsView: View {
    let settings: [String: JSONValue]
    @Environment(RemoteStore.self) private var store
    @State private var delivery: NotificationDelivery?

    var body: some View {
        Form {
            Section {
                RemoteToggle(AppCopy.Notifications.show, value: settings["enabled"]?.bool ?? false) { on in
                    await set("enabled", .bool(on))
                }
            }
            Section {
                RemoteToggle(AppCopy.Notifications.replies, value: settings["replies"]?.bool ?? true) { on in
                    await set("replies", .bool(on))
                }
                ForEach(kinds, id: \.self) { kind in
                    RemoteToggle(AppCopy.Notifications.kind(kind), value: kindsObject[kind]?.bool ?? false) { on in
                        await setKind(kind, on)
                    }
                }
            } header: {
                Text(AppCopy.Notifications.notifyAbout)
            }
            .disabled(settings["enabled"]?.bool != true)
            Section {
                RemoteMenuPicker(
                    AppCopy.Notifications.preview,
                    choices: AppCopy.Notifications.previewOrder.map {
                        Choice(id: $0, title: AppCopy.Notifications.previewName($0))
                    },
                    value: preview
                ) { choice in
                    await set("preview", .string(choice))
                }
            } footer: {
                Text(AppCopy.Notifications.previewNote(preview) ?? AppCopy.Notifications.note)
            }
            .disabled(settings["enabled"]?.bool != true)
            if let delivery {
                DeliverySection(delivery: delivery) { await loadDelivery() }
            }
        }
        // These are the Mac's banners, not this iPhone's (UX audit U-39), as "Appearance on Your Mac" says of its own.
        .navigationTitle(AppCopy.SettingsTab.notificationsOnYourMac)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)  // as a large title it read "Notifications on Your M…" (U-62)
        #endif
        .task { await loadDelivery() }
        .refreshable { await loadDelivery() }
    }

    /// Quiet: what the Mac's banners did is a read that changes nothing; a failure leaves the block as it was.
    private func loadDelivery() async {
        guard store.bridgeOffers("notification_status") else { return }
        let earlier = store.notice
        if let read = try? await store.notificationDelivery() {
            delivery = read
        } else {
            store.notice = earlier
        }
    }

    private var preview: String { settings["preview"]?.string ?? "title" }
    private var kindsObject: [String: JSONValue] { settings["kinds"]?.object ?? [:] }

    /// Pebble's kinds in its order, then any a newer Pebble adds.
    private var kinds: [String] {
        let known = AppCopy.Notifications.kindOrder.filter { kindsObject[$0] != nil }
        return known + kindsObject.keys.filter { !known.contains($0) }.sorted()
    }

    private func set(_ key: String, _ value: JSONValue) async -> Bool {
        var next = settings
        next[key] = value
        return await store.attempt { try await store.setNotifications(.object(next)) }
    }

    private func setKind(_ kind: String, _ on: Bool) async -> Bool {
        var next = kindsObject
        next[kind] = .bool(on)
        return await set("kinds", .object(next))
    }
}

/// The Mac's Delivery block: Waiting · Shown · Not shown · Failed, quiet hours and the last problem, then each schedule
/// with its banners on or muted and Mute or Unmute (its updates stay in Pebble either way). What a change did is said
/// under it, and to VoiceOver.
private struct DeliverySection: View {
    let delivery: NotificationDelivery
    /// Reads the block again.
    let reload: () async -> Void
    @Environment(RemoteStore.self) private var store
    @State private var changing: String?
    @State private var said: String?

    var body: some View {
        Section {
            Text(
                AppCopy.Delivery.outbox(
                    waiting: delivery.waiting, shown: delivery.shown, notShown: delivery.notShown,
                    failed: delivery.failed, held: delivery.heldForQuietHours))
            if delivery.quietHoursNow {
                Text(AppCopy.Delivery.quietNow)
            }
            if let problem = delivery.lastProblem {
                Text(AppCopy.Delivery.problem(problem))
            }
            ForEach(delivery.schedules) { schedule in
                HStack {
                    // The schedule's name is Pebble's data: verbatim, with the state after it, as the Mac writes it.
                    let state = Text(AppCopy.Delivery.state(muted: schedule.muted)).foregroundStyle(.secondary)
                    Text("\(Text(verbatim: schedule.label))\(state)")
                    Spacer()
                    if changing == schedule.id {
                        ProgressView()
                    } else if store.bridgeOffers("notification_mute") {
                        Button {
                            toggle(schedule)
                        } label: {
                            Text(schedule.muted ? AppCopy.Delivery.unmute : AppCopy.Delivery.mute)
                                .tapTarget()
                        }
                        .buttonStyle(.borderless)
                        .disabled(changing != nil)
                        .accessibilityLabel(AppCopy.Delivery.label(schedule.label, muted: schedule.muted))
                    }
                }
            }
            if delivery.schedules.isEmpty {
                Text(AppCopy.Delivery.noSchedules)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(AppCopy.Delivery.section)
        } footer: {
            if let said {
                Text(said)
            }
        }
    }

    private func toggle(_ schedule: NotificationDelivery.Schedule) {
        guard changing == nil else { return }
        changing = schedule.id
        Task {
            if await store.attempt({ try await store.muteBanners(of: schedule, !schedule.muted) }) {
                let words =
                    schedule.muted ? AppCopy.Delivery.unmuted(schedule.label) : AppCopy.Delivery.muted(schedule.label)
                said = words
                AccessibilityNotification.Announcement(words).post()
                await reload()
            }
            changing = nil
        }
    }
}

