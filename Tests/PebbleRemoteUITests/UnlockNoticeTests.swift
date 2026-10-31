import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// C1: a refusal that needs the unlock opens the unlock sheet, not the app-wide alert.
struct UnlockNoticeTests {
    @Test func unlockRequiredDoesNotRaiseTheAlert() {
        let store = RemoteStore.demo(pace: 0)
        store.notice = PersonFacingError(message: "Unlock with Face ID first.", code: RemoteStore.unlockRequiredCode)
        #expect(!store.isShowingNotice)
    }

    @Test func otherRefusalsDo() {
        let store = RemoteStore.demo(pace: 0)
        store.notice = PersonFacingError(message: "Pebble won't change the mode while a task runs.", code: "busy")
        #expect(store.isShowingNotice)
        store.isShowingNotice = false
        #expect(store.notice == nil)
    }
}
