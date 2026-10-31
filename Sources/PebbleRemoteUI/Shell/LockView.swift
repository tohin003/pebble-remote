import PebbleDesign
import SwiftUI

/// What shows while the app is locked: nothing of the person's chats, one way to unlock.
struct LockView: View {
    @Environment(AppLock.self) private var lock
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize = 96

    var body: some View {
        VStack {
            Spacer()
            PebbleAvatar(pose: .sleepy, animated: false)
                .frame(width: avatarSize, height: avatarSize)
            Text(AppCopy.FaceID.locked)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
            if let problem = lock.problem {
                Text(problem)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(AppCopy.FaceID.unlockButton, systemImage: "faceid", action: unlock)
                .buttonStyle(.pebbleGlassProminent)
                .controlSize(.large)
                .disabled(lock.isUnlocking)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func unlock() {
        Task { await lock.unlock() }
    }
}
