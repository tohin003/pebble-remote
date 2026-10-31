import SwiftUI

/// Covers a view with the lock screen while the app is locked. Applied at the root and inside every sheet, because a
/// sheet sits above the root's overlay.
struct LockCover: ViewModifier {
    @Environment(AppLock.self) private var lock

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(lock.isLocked)
            .overlay {
                if lock.isLocked {
                    LockView()
                }
            }
    }
}

extension View {
    func lockCover() -> some View {
        modifier(LockCover())
    }
}
