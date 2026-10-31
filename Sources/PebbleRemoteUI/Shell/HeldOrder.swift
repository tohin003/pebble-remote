/// A list's order, held while the person touches or scrolls it, so a row never moves under their finger (the UX
/// audit's U-31: a run that finished moved its conversation to the top as the person tapped another). While held, the
/// rows that are still there keep their places, with their newest content; a row that went away goes at once; a new
/// row waits until the order is released, a moment after the list comes to rest.
enum HeldOrder {
    /// How long after the list comes to rest the held order lets go.
    static let release: Duration = .seconds(1)

    /// `items` in the held order (by id), or as they come when nothing is held.
    static func apply<Item: Identifiable>(_ held: [Item.ID]?, to items: [Item]) -> [Item] {
        guard let held else { return items }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return held.compactMap { byID[$0] }
    }
}
