import AppKit

/// A display-ready grid entry, decoupled from the API model.
struct GridEntry {
    let title: String
    let subtitle: String?
    let poster: String?
    let placeholder: String
    let badge: String?
    let action: () -> Void
}

/// NSCollectionView item wrapping a PosterCard.
final class PosterItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PosterItem")
    private let card = PosterCard()

    override func loadView() { view = card }

    func configure(_ entry: GridEntry) {
        card.configure(title: entry.title, subtitle: entry.subtitle, posterURL: entry.poster,
                       placeholder: entry.placeholder, badgeText: entry.badge)
        card.onClick = entry.action
    }
}
