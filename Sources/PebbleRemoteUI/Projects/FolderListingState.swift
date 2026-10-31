import PebbleDesign
import SwiftUI

/// Over a folder's list while it has nothing to show: loading, why it couldn't be listed (with Try Again), or no folders.
struct FolderListingState: View {
    let isLoading: Bool
    let problem: String?
    let isEmpty: Bool
    let retry: () -> Void

    var body: some View {
        if isLoading {
            ProgressView(AppCopy.ConnectProject.loading)
        } else if let problem {
            ContentUnavailableView {
                Label(AppCopy.ConnectProject.couldNotListTitle, systemImage: PebbleSymbol.status(.error))
            } description: {
                Text(problem)
            } actions: {
                Button(AppCopy.Common.retry, action: retry)
            }
        } else if isEmpty {
            ContentUnavailableView(
                AppCopy.ConnectProject.noFoldersTitle, systemImage: PebbleSymbol.project,
                description: Text(AppCopy.ConnectProject.noFoldersDescription))
        }
    }
}
