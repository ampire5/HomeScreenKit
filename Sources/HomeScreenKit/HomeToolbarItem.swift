import AppKit

/// The items of the browser's `NSToolbar`, with the order a narrow window hides them in.
enum HomeToolbarItem: CaseIterable {
    case title, home, history, path, aspect, filter, sort, zoom, progress, cards, search

    var identifier: NSToolbarItem.Identifier {
        switch self {
        case .title: .init("home.title")
        case .home: .init("home.start")
        case .history: .init("home.history")
        case .path: .init("home.path")
        case .aspect: .init("home.aspect")
        case .filter: .init("home.filter")
        case .sort: .init("home.sort")
        case .zoom: .init("home.zoom")
        case .progress: .init("home.progress")
        case .cards: .init("home.cards")
        case .search: .init("home.search")
        }
    }

    var priority: Int {
        switch self {
        case .title: 1000
        case .cards: -250
        case .aspect: -100
        case .sort: -90
        case .filter: 900
        case .history: 0
        case .home: 10
        case .path: 50
        case .progress: 80
        case .search: 100
        case .zoom: 300
        }
    }

    /// As Finder's: the buttons first, then the title, so a long name takes the room up to the filter and moves none of
    /// them; the card size on the right, beside the card styles.
    static let browserOrder: [NSToolbarItem.Identifier] =
        [.flexibleSpace, .toggleSidebar, .sidebarTrackingSeparator] + [HomeToolbarItem.home, .history, .path, .title].map(\.identifier)
        + [.flexibleSpace, HomeToolbarItem.filter.identifier, .flexibleSpace]
        + [HomeToolbarItem.sort, .aspect, .progress, .zoom, .cards, .search].map(\.identifier)
}
