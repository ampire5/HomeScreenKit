import AppKit
import HomeScreenModel

/// What `homescreen-demo bench-toolbar` reaches in the toolbar, which is internal: `@_spi(Bench) import HomeScreenKit`.
/// Not API: nothing outside the bench calls these.
extension HomeBrowserView {
    /// The toolbar's progress pill with `state`, as `setProgress` shows it once its delay is over.
    @_spi(Bench) public func benchShow(progress state: ThumbsProgressState?) { toolbar.show(progress: state) }

    /// Every sort segment clicked in turn, as the clicks do: the source re-sorts and the grid is laid out again.
    @_spi(Bench) public func benchChooseSorts() {
        for i in 0..<3 { toolbar.clickSort(i) }   // Name, Date, Size
    }

    /// The menu of `count` sibling folders beside the folder on screen, built as when its submenu of the path pill opens
    /// and the listing arrives.
    @_spi(Bench) public func benchOpenSiblings(count: Int) {
        let entries = (0..<count).map { (title: "Sibling \($0)", location: BrowserLocation.folder(URL(fileURLWithPath: "/Demo/Sibling \($0)")),
                                         current: $0 == 0) }
        toolbar.openPathMenu()
        let crumb = toolbar.pathMenuTitles.count - 1
        toolbar.openSiblingMenu(atPathItem: 0)
        toolbar.showSiblings(nil, at: crumb)
        toolbar.updateSiblings(entries)
        toolbar.closeSiblings()
    }
}
