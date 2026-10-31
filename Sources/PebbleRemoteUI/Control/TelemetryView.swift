import Accessibility
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Settings › Privacy & Stealth › Usage Telemetry, as the Mac's section is (TelemetrySettings.vue): whether it is on,
/// the notice (Pebble's text, literally), the limits and what each event can contain. Off, it turns on only after the
/// person switches on "I have read this notice and want to turn telemetry on", and sends the version of the notice
/// shown. On, "Turn Off and Delete the Log". Save a copy and Clear log stay on the Mac: one row.
struct TelemetryView: View {
    @Environment(RemoteStore.self) private var store
    @State private var status: TelemetryStatus?
    @State private var hasReadNotice = false
    @State private var isWorking = false
    /// What the last change did (Pebble's words).
    @State private var done: String?
    @State private var isLoaded = false

    var body: some View {
        Form {
            if let status {
                Section {
                    Text(statusLine(status))
                    Text(verbatim: status.notice)
                        .textSelection(.enabled)
                    Text(
                        AppCopy.Telemetry.limits(
                            events: status.maxEvents, kilobytes: status.maxKilobytes, days: status.retentionDays)
                    )
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                    if !status.fields.isEmpty {
                        DisclosureGroup(AppCopy.Telemetry.whatEachEventHolds) {
                            ForEach(status.fields) { field in
                                Text(verbatim: AppCopy.Telemetry.field(field.kind, field.names))
                                    .font(PebbleFont.meta)
                            }
                        }
                    }
                }
                if status.enabled {
                    enabledSection(status)
                } else {
                    Section {
                        Toggle(AppCopy.Telemetry.agree, isOn: $hasReadNotice)
                            .disabled(isWorking)
                        working(AppCopy.Telemetry.turnOn, role: nil) { turnOn(status) }
                            .disabled(!hasReadNotice || status.consentVersion.isEmpty || isWorking)
                    }
                }
                if let done {
                    Section {
                        Text(done)
                    }
                }
            } else if !isLoaded {
                ProgressView()
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle(AppCopy.Telemetry.title)
    }

    private func enabledSection(_ status: TelemetryStatus) -> some View {
        Group {
            Section {
                if status.dropped + status.expired + status.refused > 0 {
                    Text(
                        AppCopy.Telemetry.removed(
                            dropped: status.dropped, expired: status.expired, refused: status.refused))
                }
                if let id = status.installID {
                    Text(AppCopy.Telemetry.randomID(id))
                        .textSelection(.enabled)
                }
                working(AppCopy.Telemetry.turnOff, role: .destructive) { turnOff() }
                    .disabled(isWorking)
            }
            Section {
                OnYourMacRow(title: AppCopy.Telemetry.onYourMac)
            } footer: {
                Text(AppCopy.Telemetry.onYourMacNote)
            }
        }
    }

    /// "On since … · 3 events kept · …" or "Off · nothing is collected · …".
    private func statusLine(_ status: TelemetryStatus) -> String {
        guard status.enabled else { return AppCopy.Telemetry.statusOff }
        let since =
            status.consentedAt?.formatted(date: .abbreviated, time: .shortened) ?? AppCopy.Telemetry.unknownSince
        return AppCopy.Telemetry.statusOn(since: since, events: status.events)
    }

    private func working(_ title: String, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                if isWorking {
                    Spacer()
                    ProgressView()
                }
            }
            .contentShape(.rect)
        }
    }

    /// A failure leaves what the screen shows, and the store's notice says why.
    private func load() async {
        if let read = await store.attempt({ try await store.telemetry() }) {
            status = read
        }
        isLoaded = true
    }

    private func turnOn(_ shown: TelemetryStatus) {
        guard hasReadNotice, !isWorking else { return }
        isWorking = true
        Task {
            if let next = await store.attempt({ try await store.turnOnTelemetry(readNotice: shown) }) {
                status = next
                hasReadNotice = false
                if next.enabled { say(AppCopy.Telemetry.turnedOn) }
            }
            isWorking = false
        }
    }

    private func turnOff() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            if let next = await store.attempt({ try await store.turnOffTelemetry() }) {
                status = next
                say(AppCopy.Telemetry.turnedOff)
            }
            isWorking = false
        }
    }

    private func say(_ words: String) {
        done = words
        AccessibilityNotification.Announcement(words).post()
    }
}
