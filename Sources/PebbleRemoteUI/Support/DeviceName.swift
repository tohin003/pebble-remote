import Foundation
import SwiftUI

/// The name this phone gives the Mac when it pairs (shown in Pebble's list of paired phones).
enum DeviceName {
    static var current: String {
        #if os(iOS)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }
}
