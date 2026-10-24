import AppKit
@testable import HomeScreenKit
@testable import HomeScreenModel

/// The toolbar as the browser's tests read it: the path comes out of its menu, which is filled when opened, and a click
/// is the click on the menu's item.
extension HomeToolbarController {
    /// The crumbs from the places down.
    var crumbTitles: [String] {
        openPathMenu()
        return pathMenuTitles.reversed()
    }

    func clickCrumb(_ i: Int) {
        openPathMenu()
        let item = pathMenuTitles.count - 1 - i
        if i == 0 { clickPathItem(item) } else { clickPathOpen(item) }   // the first crumb has no submenu
    }

    /// The sort fields' segments, the active one with its arrow.
    var sortTitles: [String] { sortSegmentTitles }

    /// The submenu of the folders beside crumb `i`, opened.
    func clickSiblings(_ i: Int) {
        openPathMenu()
        openSiblingMenu(atPathItem: pathMenuTitles.count - 1 - i)
    }
}
