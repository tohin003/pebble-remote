import SwiftUI

/// Pebble's desktop type scale (tokens.css `--text-xs/sm/md/lg`: 11, 12, 13, 15 px; messages 14 px; headings 17 and
/// 22 px) mapped onto Dynamic Type text styles by role, so every size follows the person's text setting. San Francisco
/// throughout, as on Pebble's desktop (`-apple-system`). No light weights; `.caption2` is never used.
///
/// | Pebble (desktop)                   | Role here      | iOS style                    |
/// |------------------------------------|----------------|------------------------------|
/// | 22 px heading                      | screen titles  | navigation title (system)    |
/// | 17 px heading, 15 px `--text-lg`   | `title`        | `.title3`, semibold          |
/// | 14 px message text                 | `message`      | `.body`                      |
/// | 13 px card title (V1-040)          | `cardTitle`    | `.headline`                  |
/// | 12 px card body, diff, command     | `cardDetail`   | `.callout` monospaced        |
/// | 12 px status line                  | `statusWord`   | `.subheadline`, medium       |
/// | 11 px chips, footers               | `chip`, `meta` | `.footnote`                  |
/// | 12.5 px inline code                | `code`         | `.callout` monospaced        |
nonisolated public enum PebbleFont {
    /// A section or hero heading inside a screen.
    public static let title: Font = .title3.weight(.semibold)
    /// Message text, yours and Pebble's.
    public static let message: Font = .body
    /// A Markdown heading inside a reply.
    public static let messageHeading: Font = .headline
    /// The one plain sentence on a review card: what approving does. The most important text in the app.
    public static let cardTitle: Font = .headline
    /// The exact thing to approve (command, path, address): monospaced so every character is visible.
    public static let cardDetail: Font = .callout.monospaced()
    /// Supporting sentences on a card.
    public static let cardBody: Font = .subheadline
    /// The status word ("Editing"): Pebble's status line uses weight 500.
    public static let statusWord: Font = .subheadline.weight(.medium)
    /// Elapsed time next to a status word ("2 min 05 s"): tabular digits so it doesn't jitter.
    public static let elapsed: Font = .subheadline.monospacedDigit()
    /// Chips and badges (mode, status).
    public static let chip: Font = .footnote.weight(.medium)
    /// Metadata: times, conversation names, footers.
    public static let meta: Font = .footnote
    /// Code in replies, inline and in blocks.
    public static let code: Font = .callout.monospaced()
    /// Activity lines under a reply ("Edited App.vue").
    public static let activity: Font = .footnote
}
