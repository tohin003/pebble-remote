/// One option in a `ChoiceList`: what the Mac calls it (`id`) and what the person reads.
struct Choice: Identifiable, Hashable {
    let id: String
    let title: String
    var detail: String? = nil
}
