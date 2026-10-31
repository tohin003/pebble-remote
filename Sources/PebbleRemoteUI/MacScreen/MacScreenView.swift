import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The Mac's screen as the phone last asked for it (C3): full screen, zoomable, with a display picker when the Mac has
/// more than one, Refresh, and Share (the only way the picture leaves memory). Media-first, so it sits on black.
/// Under the picture: when it was taken, and Pebble's note on what happens to it (the Mac keeps no copy; this iPhone
/// keeps it only if you share it), plus the Stealth note while Stealth Lockdown is on.
struct MacScreenView: View {
    /// Takes a screenshot: nil asks for every display.
    let load: (Int?) async throws -> MacScreenCapture
    /// Stealth Lockdown is on: Pebble's own windows stay out of the picture, and the note says so.
    var stealth = false
    @State private var capture: MacScreenCapture?
    @State private var selected: Int?
    @State private var isLoading = false
    @State private var problem: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let display = shownDisplay {
                // Kept clear of the note below it: a zoomed picture under those words would make both hard to read.
                ZoomableImage(image: display.image, label: AppCopy.MacScreen.imageLabel)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let problem {
                ContentUnavailableView(
                    AppCopy.MacScreen.title, systemImage: "display", description: Text(problem))
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle(AppCopy.MacScreen.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            MacScreenToolbar(
                capture: capture, selected: $selected, shown: shownDisplay, isLoading: isLoading, refresh: refresh)
        }
        .safeAreaInset(edge: .bottom) {
            if let capture {
                VStack(spacing: PebbleSpace.s1) {
                    Text(AppCopy.MacScreen.takenAt(capture.takenAt.formatted(date: .omitted, time: .standard)))
                    Text(AppCopy.MacScreen.note)
                    if stealth {
                        Text(AppCopy.MacScreen.stealthNote)
                    }
                }
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.vertical, PebbleSpace.s2)
            }
        }
        .task { await reload() }
    }

    /// The chosen display, or the first.
    private var shownDisplay: MacScreenCapture.Display? {
        guard let capture else { return nil }
        return capture.displays.first { $0.index == selected } ?? capture.displays.first
    }

    private func refresh() {
        Task { await reload() }
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await load(nil)
            capture = next
            problem = next.displays.isEmpty ? AppCopy.MacScreen.nothingCaptured : nil
            if !next.displays.contains(where: { $0.index == selected }) { selected = next.displays.first?.index }
        } catch {
            problem = Self.words(for: error)
        }
    }

    /// The Mac's refusal in its own words (no Screen Recording permission, Stealth); otherwise plain words.
    static func words(for error: any Error) -> String? {
        switch error as? RemoteCallError {
        case .refused(let refusal)?: refusal.message
        case .notImplemented?: AppCopy.Control.notYet
        case .cancelledByPerson?: nil
        case .notConnected?: AppCopy.Errors.notConnected
        case .timedOut?: AppCopy.Errors.timedOut
        default: AppCopy.Errors.generic
        }
    }
}
