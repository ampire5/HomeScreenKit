import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct HomeToolbarItemTests {
    /// A narrow window hides the item with the least priority first; the location text goes last.
    @Test func hideOrderFollowsTheSpec() {
        let order = HomeToolbarItem.allCases.sorted { $0.priority < $1.priority }
        #expect(order == [.cards, .aspect, .sort, .history, .home, .path, .progress, .search, .zoom, .filter, .title])
        let priorities = HomeToolbarItem.allCases.map(\.priority)
        #expect(Set(priorities).count == priorities.count)
    }

    @Test func browserOrderHasCenteredFilterAndEveryItemOnce() {
        let order = HomeToolbarItem.browserOrder
        #expect(order.filter { $0 == .flexibleSpace }.count == 3)
        let center = order.firstIndex(of: HomeToolbarItem.filter.identifier)!
        #expect(order[center - 1] == .flexibleSpace && order[center + 1] == .flexibleSpace)
        let systemItems: Set<NSToolbarItem.Identifier> = [.toggleSidebar, .sidebarTrackingSeparator]
        let items = order.filter { $0 != .flexibleSpace && !systemItems.contains($0) }
        #expect(items == HomeToolbarItem.allCases.map(\.identifier).sorted { rank($0) < rank($1) })
        #expect(Set(items).count == items.count)
        #expect(Array(order.prefix(3)) == [.flexibleSpace, .toggleSidebar, .sidebarTrackingSeparator])
        #expect(order[center - 2] == HomeToolbarItem.title.identifier)   // the title runs up to the filter's room
    }

    /// The layout left to right, as the spec draws it.
    private func rank(_ id: NSToolbarItem.Identifier) -> Int {
        let left: [HomeToolbarItem] = [.home, .history, .path, .title, .filter, .sort, .aspect, .progress, .zoom, .cards, .search]
        return left.firstIndex { $0.identifier == id } ?? -1
    }

    @Test func identifiersAreDistinct() {
        let ids = HomeToolbarItem.allCases.map(\.identifier)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.rawValue.hasPrefix("home.") })
    }
}
