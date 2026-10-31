import PebbleRemoteKit

/// Stop, Pause and Resume for a chat's run, shared by the run bar and the conversation's menu. Failures become the
/// store's notice; `done` runs only when Pebble took the change (the screens play the "stopped" haptic there).
enum RunActions {
    static func stop(_ chat: ChatID, store: RemoteStore, done: @escaping () -> Void = {}) {
        Task {
            if await store.attempt({ try await store.stop(chat: chat) }) { done() }
        }
    }

    static func togglePause(_ transcript: Transcript, store: RemoteStore, done: @escaping () -> Void = {}) {
        guard let run = transcript.run else { return }
        let chat = transcript.chatID
        let isPaused = run.state == .paused
        Task {
            let took = await store.attempt {
                if isPaused {
                    try await store.resume(chat: chat)
                } else {
                    try await store.pause(chat: chat)
                }
            }
            if took { done() }
        }
    }
}
