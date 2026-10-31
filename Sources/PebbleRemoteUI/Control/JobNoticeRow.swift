import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A notice a schedule left for the person ("Daily summary finished"), with OK to clear it.
struct JobNoticeRow: View {
    let notice: JobNotice
    @Environment(RemoteStore.self) private var store
    @State private var isClearing = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(notice.title)
                if let created = notice.created {
                    Text(created.formatted(.relative(presentation: .named)))
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: clear) {
                Text(AppCopy.Common.ok)
                    .tapTarget()
            }
            .buttonStyle(.borderless)
            .disabled(isClearing)
        }
    }

    private func clear() {
        isClearing = true
        Task {
            await store.attempt { try await store.acknowledge(notice) }
            isClearing = false
        }
    }
}
