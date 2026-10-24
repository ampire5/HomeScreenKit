import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct HomeToolbarItemTests {
    /// A narrow window hides the item with the least priority first (spec, "Узкое окно"): `View ▾`, the card switch,
    /// `− +`, the filter, ‹ ›, Start Page, the path, the ring, the search, and the sidebar last.
    @Test func hideOrderFollowsTheSpec() {
        let order = HomeToolbarItem.allCases.filter { $0 != .pageFilter }.sorted { $0.priority < $1.priority }
        #expect(order == [.view, .cards, .zoom, .filter, .history, .home, .path, .progress, .search, .sidebar])
        #expect(HomeToolbarItem.pageFilter.priority == HomeToolbarItem.filter.priority)
        let priorities = HomeToolbarItem.allCases.filter { $0 != .pageFilter }.map(\.priority)
        #expect(Set(priorities).count == priorities.count)
    }

    @Test func browserOrderHasEveryItemOnceAndTwoFlexibleSpaces() {
        let order = HomeToolbarItem.browserOrder
        #expect(order.filter { $0 == .flexibleSpace }.count == 2)
        let items = order.filter { $0 != .flexibleSpace }
        #expect(items == HomeToolbarItem.allCases.map(\.identifier).sorted { rank($0) < rank($1) })
        #expect(Set(items).count == items.count)
        let filter = order.firstIndex(of: HomeToolbarItem.filter.identifier)
        #expect(filter.map { order[$0 + 1] } == HomeToolbarItem.pageFilter.identifier)
    }

    /// The layout left to right, as the spec draws it.
    private func rank(_ id: NSToolbarItem.Identifier) -> Int {
        let left: [HomeToolbarItem] = [.sidebar, .home, .history, .path, .filter, .pageFilter, .progress, .cards, .zoom, .view, .search]
        return left.firstIndex { $0.identifier == id } ?? -1
    }

    @Test func identifiersAreDistinct() {
        let ids = HomeToolbarItem.allCases.map(\.identifier)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.rawValue.hasPrefix("home.") })
    }
}
