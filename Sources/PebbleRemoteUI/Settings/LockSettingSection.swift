import PebbleDesign
import SwiftUI

/// "Unlock with Face ID" (on by default) in a section of its own, with its note under it.
struct LockSettingSection: View {
    var body: some View {
        Section {
            LockSettingRow(showsNote: false)
        } footer: {
            Text(AppCopy.Settings.unlockWithFaceIDNote)
        }
    }
}

/// "Unlock with Face ID" (on by default) as one row, its note under its name (Settings › iPhone). Turning it off asks
/// for Face ID first, so a borrowed, unlocked phone can't switch the lock off.
struct LockSettingRow: View {
    var showsNote = true
    @AppStorage(AppLock.settingKey) private var isOn = true
    @State private var isChecking = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppCopy.Settings.unlockWithFaceID)
                if showsNote {
                    Text(AppCopy.Settings.unlockWithFaceIDNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isChecking)
        .onChange(of: isOn) { wasOn, nowOn in
            if wasOn, !nowOn, !isChecking { confirmTurningOff() }
        }
    }

    private func confirmTurningOff() {
        isChecking = true
        Task {
            let outcome = await AppLock.authenticate(reason: AppCopy.FaceID.turnOffLockReason)
            if outcome != .success && outcome != .unavailable {
                isOn = true
            }
            isChecking = false
        }
    }
}
