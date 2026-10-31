import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The phones paired with the Mac (`remote.devices`), each with Remove, confirmed first. Removing this iPhone ends its
/// connection, as removing it on the Mac does.
struct PairedPhonesList: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        ActionList(
            title: AppCopy.Devices.title, items: store.devices.map(Self.item),
            load: { await store.loadControlLists() }, perform: remove
        ) {
            ContentUnavailableView(AppCopy.Devices.title, systemImage: "iphone")
        }
    }

    private static func item(_ device: MacDevice) -> ActionItem {
        ActionItem(
            id: device.id,
            title: device.isCurrent ? AppCopy.Devices.thisPhone(device.name) : device.name,
            detail: device.lastSeen.map { AppCopy.Devices.lastSeen($0.formatted(.relative(presentation: .named))) },
            symbol: "iphone",
            actionTitle: AppCopy.Control.remove,
            isDestructive: true,
            confirmation: device.isCurrent ? AppCopy.Devices.removeThisPhone : AppCopy.Devices.remove(device.name))
    }

    private func remove(_ item: ActionItem) async -> Bool {
        guard let device = store.devices.first(where: { $0.id == item.id }) else { return false }
        return await store.attempt { try await store.revokeDevice(device) }
    }
}
