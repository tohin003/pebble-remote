import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The sheets a task's controls open: the uncertain outcomes, Resume's new limits, what a card holds, and a command's
/// typing, inspection and output. The screen that shows the rows presents them (a row in a lazy stack may be dropped
/// while its sheet is up), so rows ask through `RecoveryPresenter`.
enum RecoverySheet: Identifiable {
    case outcomes(TaskAttention)
    case limits(TaskAttention)
    case cardDetails(ReviewItem)
    case typeInto(ProcessJob)
    case inspect(ProcessJob)
    case output(ProcessJob)

    var id: String {
        switch self {
        case .outcomes(let task): "outcomes/\(task.id)"
        case .limits(let task): "limits/\(task.id)"
        case .cardDetails(let item): "card/\(item.id)"
        case .typeInto(let job): "type/\(job.id)"
        case .inspect(let job): "inspect/\(job.id)"
        case .output(let job): "output/\(job.id)"
        }
    }
}

/// How a row opens a recovery sheet on its screen.
typealias RecoveryPresenter = (RecoverySheet) -> Void

/// One recovery sheet.
struct RecoverySheetView: View {
    let which: RecoverySheet

    var body: some View {
        switch which {
        case .outcomes(let task): UncertainOutcomesSheet(task: task)
        case .limits(let task): ResumeLimitsSheet(task: task)
        case .cardDetails(let item): CardDetailsSheet(item: item)
        case .typeInto(let job): TypeIntoCommandSheet(job: job)
        case .inspect(let job): InspectCommandSheet(job: job)
        case .output(let job): CommandOutputSheet(job: job)
        }
    }
}

/// A sheet's own failure line: Pebble's words for what didn't go through, shown in the sheet rather than under it.
struct SheetFailure: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
