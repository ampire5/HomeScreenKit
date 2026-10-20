import AppKit
import Foundation
import HomeScreenModel

/// What the app says about one of its sources (`BrowserLocation.source`): a list the browser draws on its grid (Recent,
/// Sessions), or a page of the app's own under the toolbar (Stash).
public struct HomeSourceInfo {
    public var title: String
    /// The sort capsule's fields, in order (⌥1 is the first); none hides it.
    public var sortKeys: [BrowserSort.Key]
    /// Sorted by date, the cards fall into Today, Yesterday, This Week and Earlier.
    public var groupsByDate: Bool
    /// What the footer counts (`3 sessions`).
    public var noun: String
    /// Shown in the middle while the list is empty.
    public var emptyHint: String
    /// The app's view in place of the grid; nil: a list on the grid.
    public var page: NSView?
    /// The page's filter in the toolbar's middle (`pageFilterChosen` gets the index).
    public var pageFilters: [String]

    public init(title: String, sortKeys: [BrowserSort.Key] = [], groupsByDate: Bool = false, noun: String = "item",
                emptyHint: String = "", page: NSView? = nil, pageFilters: [String] = []) {
        self.title = title
        self.sortKeys = sortKeys
        self.groupsByDate = groupsByDate
        self.noun = noun
        self.emptyHint = emptyHint
        self.page = page
        self.pageFilters = pageFilters
    }
}

/// What the app gives Home: the sidebar, the places, the listings of folders and of its own sources, the pictures and
/// what is done to files. The browser sorts, keeps the history and the selection, and draws; it never touches a file
/// itself.
@MainActor public protocol HomeSource: AnyObject {
    /// The top level: the home folder, the volumes, pinned folders (the Places crumb's menu).
    func places() async -> [BrowserEntry]
    /// A location's listings, as they come: the places, a folder, or a list source; the browser stops iterating when it
    /// leaves the location.
    func list(_ location: BrowserLocation) -> AsyncThrowingStream<BrowserListing, Error>
    /// The folders and archives in `folder` (names are enough), for the path's sibling menus and the sidebar's tree: from
    /// the source's cache when it has the listing, so the menu fills at once.
    func folders(in folder: URL) async -> [BrowserEntry]
    /// Where Up goes from `folder`: its parent, or the places from a volume's root.
    func parent(of folder: URL) -> BrowserLocation
    /// The SF Symbol on a card that has no picture yet.
    func symbol(for entry: BrowserEntry) -> String
    /// The cards on screen want pictures, those in view first; they come back through `HomeBrowserView.setImage`.
    func wantImages(_ ids: [String], width: CGFloat)
    func menu(for entry: BrowserEntry, in location: BrowserLocation) -> [HomeMenuItem]
    func perform(_ item: String, on entry: BrowserEntry, in location: BrowserLocation)
    /// A file or a collection opened (a folder or an archive is entered by the browser itself).
    func open(_ entry: BrowserEntry, in location: BrowserLocation, sort: BrowserSort, how: HomeClick)
    func rename(_ entry: BrowserEntry, to name: String) async throws -> BrowserEntry
    func trash(_ entry: BrowserEntry) async throws
    func sort(for location: BrowserLocation) -> BrowserSort
    func setSort(_ sort: BrowserSort, for location: BrowserLocation)
    func info(for source: String) -> HomeSourceInfo
    /// The sidebar's sections: the sources, the places, the app's others.
    func sidebar() async -> [HomeSidebarSection]
    /// A segment of a page's filter was chosen.
    func pageFilterChosen(_ index: Int, in source: String)
    /// The browser went from `old` (nil: the first location) to `new`: what was read for `old` alone can stop.
    func moved(from old: BrowserLocation?, to new: BrowserLocation)
}

public extension HomeSource {
    func moved(from old: BrowserLocation?, to new: BrowserLocation) {}
}
