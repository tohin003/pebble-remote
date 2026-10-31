import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One of the conversation's views in the transcript, under the reply that drew it: its kind's mark, its title
/// (literal), its kind in a word and its state. A tap opens it (full screen, or a form in its sheet).
struct ViewCard: View {
    let artifact: PebbleArtifact
    let open: () -> Void

    var body: some View {
        let state = Self.state(artifact)
        Button(action: open) {
            HStack(spacing: PebbleSpace.s3) {
                Image(systemName: ViewSymbol.kind(artifact.kind))
                    .font(.title3)
                    .foregroundStyle(PebbleColor.accent)
                    .frame(width: PebbleSize.minTap, height: PebbleSize.minTap)
                    .background(PebbleColor.soft, in: .rect(cornerRadius: PebbleRadius.sm))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Text(verbatim: artifact.title ?? AppCopy.Views.untitledView)
                        .font(PebbleFont.cardTitle)
                        .foregroundStyle(PebbleColor.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: PebbleSpace.s2) {
                        Text(AppCopy.Views.kind(artifact.kind))
                            .font(PebbleFont.meta)
                            .foregroundStyle(PebbleColor.secondaryText)
                        if let state {
                            ToneLabel(state.words, tone: state.tone)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: ViewSymbol.disclosure)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.mutedText)
                    .accessibilityHidden(true)
            }
            .padding(PebbleSpace.s3)
            .background(PebbleColor.panel, in: .rect(cornerRadius: PebbleRadius.md))
            .overlay { RoundedRectangle(cornerRadius: PebbleRadius.md).stroke(PebbleColor.line, lineWidth: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppCopy.Views.opensTheView)
    }

    /// What the card says of the view's state: a form's, a page's, one this version can't draw, or a stopped view's.
    static func state(_ artifact: PebbleArtifact) -> (words: String, tone: WorkTone)? {
        if artifact.kind == "form", artifact.form != nil { return FormAnswers.state(artifact) }
        switch artifact.view {
        case .macOnly: return (AppCopy.Views.onYourMac, .neutral)
        case .unsupported: return (AppCopy.Views.updateTheApp, .neutral)
        default: break
        }
        if artifact.status == .stopped { return (AppCopy.Views.stopped, .neutral) }
        if artifact.status == .expired { return (AppCopy.Views.expired, .neutral) }
        return nil
    }
}
