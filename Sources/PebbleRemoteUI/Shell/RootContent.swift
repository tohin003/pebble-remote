import PebbleRemoteKit
import SwiftUI

/// Pairing until a Mac is paired (or the demo runs), then the tabs; the lock above both; the notice and the
/// pairing confirmation for links opened from outside.
struct RootContent: View {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var store = store
        @Bindable var router = router
        ZStack {
            if store.pairedMac == nil && !store.isDemo {
                PairingView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: store.pairedMac == nil && !store.isDemo)
        .lockCover()
        .alert(store.notice?.message ?? "", isPresented: $store.isShowingNotice) {}
        .sheet(item: $router.pairingToConfirm) { pending in
            PairingConfirmSheet(pending: pending)
        }
        .sheet(isPresented: $router.isAskingToUnlock) {
            UnlockSheet()
                .lockCover()
        }
        .onChange(of: store.notice?.code) { _, code in
            guard code == RemoteStore.unlockRequiredCode else { return }
            store.notice = nil
            router.isAskingToUnlock = true
        }
    }
}
