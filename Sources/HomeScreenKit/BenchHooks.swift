import AppKit
import HomeScreenModel

/// What `homescreen-demo bench-toolbar` reaches in the toolbar, which is internal: `@_spi(Bench) import HomeScreenKit`.
/// Not API: nothing outside the bench calls these.
extension HomeBrowserView {
    /// The toolbar's progress pill with `state`, as `setProgress` shows it once its delay is over.
    @_spi(Bench) public func benchShow(progress state: ThumbsProgressState?) { toolbar.show(progress: state) }

    /// Every sort field chosen in turn, as a click on the toolbar's sort does: the source re-sorts and the grid is laid out
    /// again.
    @_spi(Bench) public func benchChooseSorts() {
        for i in 0..<3 { toolbar.clickSort(i) }
    }

    /// The menu of `count` sibling folders under the second crumb, built as when the › is clicked and its listing arrives;
    /// the menu is not shown (showing one tracks the mouse).
    @_spi(Bench) public func benchOpenSiblings(count: Int) {
        let entries = (0..<count).map { (title: "Sibling \($0)", location: BrowserLocation.folder(URL(fileURLWithPath: "/Demo/Sibling \($0)")),
                                         current: $0 == 0) }
        let popUp = toolbar.popUp
        toolbar.popUp = { _, _ in }
        toolbar.showSiblings(nil, at: 1)
        toolbar.updateSiblings(entries)
        toolbar.closeSiblings()
        toolbar.popUp = popUp
    }
}
