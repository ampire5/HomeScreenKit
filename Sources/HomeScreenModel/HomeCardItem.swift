/// One entry of a card's right-click menu: what the app gets back (`id`) and what the menu shows.
public struct HomeMenuItem: Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One card on the home screen: a picture (set apart, by `id`), a title and a line under it. The app decides what
/// each field holds; the view only draws it.
public struct HomeCardItem: Equatable, Sendable {
    /// The app's key for the card: clicks, menus and pictures come back with it.
    public var id: String
    public var title: String
    public var subtitle: String?
    public var tooltip: String
    /// The SF Symbol on the grey box while the card has no picture.
    public var symbol: String
    /// 0…1: a bar along the picture's bottom edge (how much is watched or viewed); nil draws none.
    public var progress: Double?
    /// A small label on the picture ("Stash"); nil draws none.
    public var badge: String?
    /// Drawn faint: the path cannot be reached now.
    public var isDimmed: Bool
    public var menu: [HomeMenuItem]
    /// The symbol on a glass tile in place of a picture (a place: a volume, the home folder); no picture is asked.
    /// Only the browser's collection cards draw it.
    public var glassSymbol: Bool

    public init(id: String, title: String, subtitle: String? = nil, tooltip: String, symbol: String,
                progress: Double? = nil, badge: String? = nil, isDimmed: Bool = false, menu: [HomeMenuItem] = [],
                glassSymbol: Bool = false) {
        self.glassSymbol = glassSymbol
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tooltip = tooltip
        self.symbol = symbol
        self.progress = progress
        self.badge = badge
        self.isDimmed = isDimmed
        self.menu = menu
    }
}

/// A run of cards under a heading; a nil title draws no heading.
public struct HomeSection: Equatable, Sendable {
    public var title: String?
    public var items: [HomeCardItem]

    public init(title: String?, items: [HomeCardItem]) {
        self.title = title
        self.items = items
    }
}

/// How the grid fits the window (`home-layout`): `fit` shrinks the cards so that all of them show, then scrolls;
/// `scroll` keeps the card size and scrolls; `fixed` never scrolls.
public enum HomeLayoutMode: String, CaseIterable, Sendable {
    case fit, scroll, fixed
}
