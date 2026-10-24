import AppKit
@testable import HomeScreenKit
@testable import HomeScreenModel

/// The toolbar as the browser's tests read it: the path and the sort fields come out of the menus, which are filled
/// when opened, and a click is the click on the menu's item.
extension HomeToolbarController {
    /// The crumbs from the places down.
    var crumbTitles: [String] {
        openPathMenu()
        return pathMenuTitles.reversed()
    }

    func clickCrumb(_ i: Int) {
        openPathMenu()
        clickPathItem(pathMenuTitles.count - 1 - i)
    }

    /// The sort fields of the View menu, the active one with its arrow.
    var sortTitles: [String] {
        openViewMenu()
        return Array(viewMenuTitles.dropFirst().prefix { !$0.isEmpty })
    }

    /// The `i`th sort field of the View menu (after the "Sort by" heading).
    func clickSort(_ i: Int) {
        openViewMenu()
        clickViewItem(1 + i)
    }

    /// The submenu of the folders beside crumb `i`, opened.
    func clickSiblings(_ i: Int) {
        openPathMenu()
        openSiblingMenu(atPathItem: pathMenuTitles.count - 1 - i)
    }
}
