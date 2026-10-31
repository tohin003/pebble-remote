import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The transcript, oldest at the top, scrolling calmly (`TranscriptScroll`):
/// - it opens at the newest line, or with the top of the card that waits for the person in view, never under the
///   navigation bar;
/// - it follows what Pebble writes only while the person is at the end (Pebble's scroll stick), and stays at the end
///   when the composer or the run bar below it changes height, so a new card is never left under the composer;
/// - a person reading above keeps their place, and only then does "Jump to Latest" show, in the bottom bar
///   (`showsJump`), where it can't cover the transcript;
/// - sending always shows the newest line.
///
/// Every row spans the scroll view's width and keeps the margin inside itself, and the stack is pinned to the scroll
/// view's width, so nothing can scroll the transcript sideways: Pebble's replies keep their 16-point margin (the UX
/// audit's U-14, U-08).
struct TranscriptList: View {
    let transcript: Transcript
    /// Grows each time the person sends; sending always shows the newest line.
    let sentCount: Int
    /// Grows each time the person taps "Jump to Latest" (in the bottom bar).
    var jumpCount = 0
    /// Whether "Jump to Latest" should show: set here, shown by the bottom bar.
    @Binding var showsJump: Bool
    var showDetails: ((RunID) -> Void)? = nil
    /// Opens a recovery sheet on the screen.
    var present: RecoveryPresenter? = nil
    @State private var position: ScrollPosition
    /// What the transcript holds on to, where the person is and whether they are scrolling: read on every scroll
    /// frame, so it is kept out of the view's state (changing it draws nothing).
    @State private var tracker: Tracker
    /// The person's last message, opened in the editor from its long press (lane Z).
    @State private var editing: MessageItem?
    /// The window's markers under messages edited or asked again on this screen (App.vue `markers`).
    @State private var markers: [MessageID: String] = [:]
    @Environment(RemoteStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        transcript: Transcript, sentCount: Int, jumpCount: Int = 0, showsJump: Binding<Bool>,
        showDetails: ((RunID) -> Void)? = nil, present: RecoveryPresenter? = nil
    ) {
        self.transcript = transcript
        self.sentCount = sentCount
        self.jumpCount = jumpCount
        _showsJump = showsJump
        self.showDetails = showDetails
        self.present = present
        let card = TranscriptScroll.openingCard(in: transcript.items)
        _position = State(initialValue: card.map { ScrollPosition(id: $0, anchor: .top) } ?? ScrollPosition(edge: .bottom))
        _tracker = State(
            initialValue: Tracker(stick: card.map(TranscriptScroll.Stick.card) ?? .end, opened: !transcript.items.isEmpty))
    }

    var body: some View {
        // The first of the cards at the end that wait for the person: while it is in view, "Jump to Latest" stays away.
        let waitingCard = TranscriptScroll.openingCard(in: transcript.items)
        // Lane G: the work view's cards and the conversation's views (contract 3.12).
        let layout = WorkTranscriptLayout(transcript)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PebbleSpace.s4) {
                if transcript.hasOlder {
                    LoadOlderButton(transcript: transcript)
                        .padding(.horizontal)
                }
                ForEach(layout.items) { item in
                    // A message carries its long-press menu (lane Z); every other line is TranscriptRow's, with the
                    // work view where Pebble sent one (lane G).
                    Group {
                        if case .message(let message) = item {
                            MessageRow(
                                message: message, menu: menu(for: message), marker: markers[message.id],
                                citesSources: citesSources
                            )
                            .environment(\.openURL, OpenURLAction { open($0, from: message) })
                        } else {
                            WorkTranscriptRow(
                                item: item, transcript: transcript, layout: layout, showDetails: showDetails,
                                present: present)
                        }
                    }
                    .padding(.horizontal)
                    .background {
                        if item.id == waitingCard {
                            Color.clear
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.frame(in: .global).minY
                                } action: { top in
                                    update { $0.waitingCardTop = top }
                                }
                        }
                    }
                }
                if !layout.trailingViews.isEmpty {
                    ViewCardList(views: layout.trailingViews)  // lane G: views whose run has no end line yet
                        .padding(.horizontal)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical)
            .containerRelativeFrame(.horizontal)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                update { $0.stack = frame }
            }
        }
        // The space between the bars, on screen: a clear view lays itself out inside the safe area, which holds the
        // navigation bar above and the bottom bar, the keyboard and the tab bar below.
        .background {
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    update { $0.visible = frame }
                }
        }
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition($position)
        // A swipe down always closes the keyboard, even in a short transcript that fits: it always gives a little.
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .onScrollPhaseChange { old, new in
            tracker.phase = new
            // The person's own scrolling decides what the transcript holds on to: the end if they came to rest
            // there, otherwise their place.
            if new == .idle, [.tracking, .interacting, .decelerating].contains(old) {
                tracker.stick = tracker.metrics.isAtEnd ? .end : .free
            }
        }
        .onChange(of: sentCount) {
            showEnd(animated: true)
        }
        .onChange(of: jumpCount) {
            showEnd(animated: true)
        }
        .onChange(of: waitingCard) { _, card in
            if card == nil { update { $0.waitingCardTop = nil } }
        }
        .onChange(of: transcript.items.isEmpty) { _, isEmpty in
            // A conversation that opened while its transcript was still loading: place it once the lines arrive.
            guard !isEmpty, !tracker.opened else { return }
            tracker.opened = true
            if let card = TranscriptScroll.openingCard(in: transcript.items) {
                tracker.stick = .card(card)
                position.scrollTo(id: card, anchor: .top)
            } else {
                showEnd(animated: false)
            }
        }
        .overlay {
            if transcript.items.isEmpty {
                if transcript.isLoading {
                    ProgressView(AppCopy.Conversation.loading)
                } else {
                    ContentUnavailableView(
                        AppCopy.Conversation.emptyTitle, systemImage: PebbleSymbol.conversation,
                        description: Text(AppCopy.Conversation.emptyDescription))
                }
            }
        }
        .sheet(item: $editing) { message in
            MessageEditSheet(original: message.text) { words in await sendEdited(words, replacing: message) }
                .lockCover()
        }
        .viewOpening()  // lane G: Pebble's views open from here, not from a row the lazy stack may unload
    }

    // MARK: - A long press on a message (lane Z)

    /// The message's menu, as Pebble's window offers it under the message (`MessageMenuRules`); none for a reply still
    /// being written.
    private func menu(for message: MessageItem) -> MessageMenu? {
        let items = MessageMenuRules.items(
            for: message, in: transcript.items, isWorking: transcript.sendsGuidance, canSend: store.bridgeOffers("send"),
            words: words(of: message)
        ) { InAppLinks.opensInBrowser($0) }
        guard !items.isEmpty else { return nil }
        return MessageMenu(items: items) { item in act(item, on: message) }
    }

    /// A finished message's code blocks and links, worked out once per text (`Tracker.menuWords`): every row on screen
    /// asks for its menu at each streamed update.
    private func words(of message: MessageItem) -> MessageMenuRules.Words? {
        guard !message.isStreaming else { return nil }
        if let kept = tracker.menuWords[message.id], kept.text == message.text { return kept }
        let words = MessageMenuRules.Words(message)
        tracker.menuWords[message.id] = words
        return words
    }

    /// Replies' source markers are links when Pebble can say what each names (TR-10).
    private var citesSources: Bool { store.bridgeOffers("research_sources") }

    /// A link tapped in a message. A source marker ([S1]) opens the page its reply's run recorded, on this iPhone (TR-10,
    /// F13); every other link goes through the app's own link rule (InAppLinks).
    private func open(_ url: URL, from message: MessageItem) -> OpenURLAction.Result {
        guard let id = MarkdownBlocks.sourceID(of: url) else {
            openURL(url)
            return .handled
        }
        let chat = transcript.chatID
        Task {
            if let page = await store.sourcePage(id, in: chat, run: message.runID) { openURL(page) }
        }
        return .handled
    }

    private func act(_ item: MessageMenu.Item, on message: MessageItem) {
        switch item {
        case .copy: MessageClipboard.copy(message.text)
        case .copyCode(let code): MessageClipboard.copy(code)
        // On this iPhone, through the app's own link rule (InAppLinks): nothing reaches the Mac (F13).
        case .openLink(let url): openURL(url)
        case .edit: editing = message
        case .retry: retry(message)
        case .retryUnavailable: break
        }
    }

    /// Retry: the question again, as a new message; this reply stays, marked as on the Mac.
    private func retry(_ reply: MessageItem) {
        guard let question = RemoteStore.question(before: reply.id, in: transcript.items) else { return }
        let chat = transcript.chatID
        Task {
            if await store.attempt({ try await store.send(question.text, in: chat) }) {
                markers[reply.id] = AppCopy.MessageMenu.askedAgain
                showEnd(animated: true)
            }
        }
    }

    /// Edit: the edited words as a new message; the old one stays, marked as on the Mac.
    private func sendEdited(_ words: String, replacing message: MessageItem) async -> Bool {
        let chat = transcript.chatID
        let sent: Bool = await store.attempt { try await store.send(words, in: chat) }
        if sent {
            markers[message.id] = AppCopy.MessageMenu.edited
            showEnd(animated: true)
        }
        return sent
    }

    /// New frames: "Jump to Latest" shows only while the person is above the end with more below and no waiting card
    /// in view, and while the transcript holds on to the end (or to the card it opened on), a change of size puts it
    /// back there: a reply that grows, a card that appears, the composer or the run bar changing height, the keyboard.
    private func update(_ change: (inout TranscriptScroll.Metrics) -> Void) {
        let old = tracker.metrics
        var new = old
        change(&new)
        guard new != old else { return }
        tracker.metrics = new
        if showsJump != new.showsJump { showsJump = new.showsJump }
        guard new.isMeasured, tracker.phase == .idle else { return }
        let resized = new.layoutChanged(from: old)
        switch tracker.stick {
        case .end:
            // After a change of size, back to resting on the bars; an empty band under the end, whenever it shows.
            if (resized && !new.restsAtEnd) || new.hasBandUnderEnd { position.scrollTo(edge: .bottom) }
        case .card(let id):
            // A card that fits above the bars with room to spare left an empty band under the end: the end is the place.
            if new.hasBandUnderEnd || !transcript.items.contains(where: { $0.id == id }) {
                tracker.stick = .end
                position.scrollTo(edge: .bottom)
            } else if resized {
                position.scrollTo(id: id, anchor: .top)
            }
        case .free:
            break
        }
    }

    /// The newest line, and the transcript follows the end from here.
    private func showEnd(animated: Bool) {
        tracker.stick = .end
        if animated && !reduceMotion {
            withAnimation { position.scrollTo(edge: .bottom) }
        } else {
            position.scrollTo(edge: .bottom)
        }
    }
}

extension TranscriptList {
    /// Kept by reference, so reading it on every scroll frame never redraws the transcript.
    final class Tracker {
        var stick: TranscriptScroll.Stick
        var metrics = TranscriptScroll.Metrics()
        var phase: ScrollPhase = .idle
        /// The opening position is placed: the transcript had lines when it opened, or they arrived since.
        var opened: Bool
        /// Each finished message's code blocks and links for its menu, by id, with the text they came from.
        var menuWords: [MessageID: MessageMenuRules.Words] = [:]

        init(stick: TranscriptScroll.Stick, opened: Bool) {
            self.stick = stick
            self.opened = opened
        }
    }
}
