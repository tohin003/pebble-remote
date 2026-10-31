import Foundation
import Testing

@testable import PebbleRemoteUI

/// The lock's state without Face ID itself (LocalAuthentication is exercised on the phone).
/// Serialized: the setting lives in UserDefaults.standard.
@Suite(.serialized)
struct AppLockTests {
    init() {
        UserDefaults.standard.removeObject(forKey: AppLock.settingKey)
    }

    @Test func onByDefault() {
        #expect(AppLock.isWanted)
    }

    @Test func locksOnlyWhereItApplies() {
        let lock = AppLock()
        lock.lock(applies: false)
        #expect(!lock.isLocked)
        lock.lock(applies: true)
        #expect(lock.isLocked)
    }

    @Test func turnedOffNeverLocks() {
        UserDefaults.standard.set(false, forKey: AppLock.settingKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLock.settingKey) }
        let lock = AppLock()
        lock.sceneEnteredBackground(applies: true)
        #expect(!lock.isLocked)
    }

    @Test func engagingTheLockSaysSoSoTheMacsUnlockEndsWithIt() {
        // S-05: the app's model ends the Mac's unlock whenever the lock engages (PebbleRemoteModel.endBridgeUnlock).
        let lock = AppLock()
        var engaged = 0
        lock.onLocked = { engaged += 1 }
        lock.lock(applies: false)
        #expect(engaged == 0)  // no Mac is paired, or the demo runs: nothing to protect
        lock.lock(applies: true)
        #expect(engaged == 1)
        lock.sceneEnteredBackground(applies: true)
        #expect(engaged == 2)
        lock.release()
        #expect(engaged == 2)  // lifting it says nothing
    }

    @Test func aLockThatIsTurnedOffNeverSaysSo() {
        UserDefaults.standard.set(false, forKey: AppLock.settingKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLock.settingKey) }
        let lock = AppLock()
        var engaged = 0
        lock.onLocked = { engaged += 1 }
        lock.sceneEnteredBackground(applies: true)
        #expect(engaged == 0 && !lock.isLocked)
    }

    @Test func backgroundLocksAndReleaseLifts() {
        let lock = AppLock()
        lock.sceneEnteredBackground(applies: true)
        #expect(lock.isLocked)
        lock.release()
        #expect(!lock.isLocked)
        #expect(lock.problem == nil)
    }
}
