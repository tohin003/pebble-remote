import PebbleProtocol
import SwiftUI

extension View {
    /// One of Pebble's views, full screen on the iPhone (a sheet on the Mac, where the package also builds).
    func viewCover(item: Binding<PebbleArtifact?>) -> some View {
        #if os(iOS)
        fullScreenCover(item: item) { artifact in
            ViewScreen(artifact: artifact)
                .lockCover()
        }
        #else
        sheet(item: item) { artifact in
            ViewScreen(artifact: artifact)
                .lockCover()
        }
        #endif
    }
}
