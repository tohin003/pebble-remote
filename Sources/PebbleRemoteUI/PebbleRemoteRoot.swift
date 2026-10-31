import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The whole app below the scene. The Xcode app target hosts only this view, with the model it owns
/// (`PebbleRemoteModel`: the store, live or demo; the lock; the router).
public struct PebbleRemoteRoot: View {
    let model: PebbleRemoteModel

    public init(model: PebbleRemoteModel) {
        self.model = model
    }

    public var body: some View {
        RootContent()
            .environment(model)
            .environment(model.store)
            .environment(model.router)
            .environment(model.lock)
            .tint(PebbleColor.accent)
            .environment(\.openURL, OpenURLAction(handler: InAppLinks.handle))
            .onOpenURL { url in model.open(url) }
    }
}
