import AppKit

/// The items of the browser's `NSToolbar`, with the order a narrow window hides them in. `visibilityPriority`: the item
/// with the least priority goes behind the `»` first; the values are all different (equal ones go in an order the system
/// picks), except the page filter, which takes the kind filter's place and is never shown with it.
enum HomeToolbarItem: CaseIterable {
    case sidebar, home, history, path, filter, pageFilter, progress, cards, zoom, view, search

    var identifier: NSToolbarItem.Identifier {
        switch self {
        case .sidebar: .init("home.sidebar")
        case .home: .init("home.start")
        case .history: .init("home.history")
        case .path: .init("home.path")
        case .filter: .init("home.filter")
        case .pageFilter: .init("home.pageFilter")
        case .progress: .init("home.progress")
        case .cards: .init("home.cards")
        case .zoom: .init("home.zoom")
        case .view: .init("home.view")
        case .search: .init("home.search")
        }
    }

    /// Measured on the real window with the probe (2026-10-24): everything shows from 1120 pt; `View` and the card switch
    /// go at 1100, `− +` at 980, the filter at 900, ‹ › at 640, Start Page at 560, the path at 480, the ring at 420.
    var priority: Int {
        switch self {
        case .view: -300
        case .cards: -250
        case .zoom: -200
        case .filter, .pageFilter: -100
        case .history: 0
        case .home: 10
        case .path: 50
        case .progress: 80
        case .search: 100
        case .sidebar: 1000
        }
    }

    /// Left to right: where I am (sidebar, start page, history, path), what is shown (the filter, the ring), how it is
    /// shown (card switch, zoom, View) and the search. The two flexible spaces centre the filter between the path and
    /// the ring.
    static let browserOrder: [NSToolbarItem.Identifier] =
        [HomeToolbarItem.sidebar, .home, .history, .path].map(\.identifier) + [.flexibleSpace]
        + [HomeToolbarItem.filter, .pageFilter].map(\.identifier) + [.flexibleSpace]
        + [HomeToolbarItem.progress, .cards, .zoom, .view, .search].map(\.identifier)
}
