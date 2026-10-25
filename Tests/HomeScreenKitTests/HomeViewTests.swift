import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeViewTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    private func source() -> FakeHomeSource {
        let source = FakeHomeSource()
        source.sidebarSections = [
            HomeSidebarSection(id: "library", title: nil, rows: [
                HomeSidebarRow(id: "recent", title: "Recent", symbol: "clock", location: .source("recent")),
            ]),
            HomeSidebarSection(id: "places", title: "Places", rows: [
                HomeSidebarRow(id: "/Volumes/T", title: "T", symbol: "externaldrive", location: .folder(url("/Volumes/T")),
                               expandable: true),
            ]),
            HomeSidebarSection(id: "stash", title: "Stash", rows: [
                HomeSidebarRow(id: "stash", title: "Library", symbol: "server.rack", location: .source("stash")),
            ]),
        ]
        source.infos["stash"] = HomeSourceInfo(title: "Stash", page: NSView())
        return source
    }

    /// A Home view in a window (the keys need one), its sidebar loaded.
    private func make(_ source: FakeHomeSource) async -> (HomeView, NSWindow) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled],
                              backing: .buffered, defer: true)
        let view = HomeView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        window.contentView = view
        await settle { !view.sidebarView.titles.isEmpty }
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    @Test func sidebarOpensSources() async {
        let source = source()
        let (view, _) = await make(source)
        view.sidebarView.click(line: 0)
        #expect(view.browser.location == .source("recent"))
        #expect(view.sidebarView.highlightedLine == 0)
        view.browser.show(.source("stash"), selecting: nil)
        #expect(view.sidebarView.highlightedLine == view.sidebarView.titles.firstIndex(of: "Library"))
    }

    @Test func treeWaitsForCurrentListing() async {
        let source = source()
        source.holdsFolders = true
        let (view, _) = await make(source)
        let b = url("/Volumes/T/A/B")
        view.browser.show(.folder(b), selecting: nil)
        #expect(view.sidebarView.titles.contains("A"))
        #expect(view.sidebarView.titles.contains("B"))
        await settle()
        #expect(source.foldersAsked.isEmpty)
        source.yield(b, BrowserFixtures.files(2, in: b.path))
        await settle { !source.foldersAsked.isEmpty }
        #expect(source.foldersAsked == [url("/Volumes/T")])
        source.answerFolders([BrowserFixtures.folder("A", in: "/Volumes/T"), BrowserFixtures.folder("Z", in: "/Volumes/T")])
        await settle { source.foldersAsked.count == 2 }
        #expect(source.foldersAsked == [url("/Volumes/T"), url("/Volumes/T/A")])
        #expect(view.sidebarView.titles.contains("Z"))
        // A move before the second reply: nothing more is asked for the old path.
        view.browser.show(.source("recent"), selecting: nil)
        source.answerFolders([BrowserFixtures.folder("B", in: "/Volumes/T/A")])
        await settle()
        #expect(source.foldersAsked.count == 2)
    }

    @Test func expandAsksAtOnce() async {
        let source = source()
        let (view, _) = await make(source)
        let x = url("/Volumes/T/x")
        view.browser.show(.folder(x), selecting: nil)   // its listing never completes
        let t = view.sidebarView.titles.firstIndex(of: "T")!
        view.sidebarView.clickDisclosure(line: t)   // open already (the path): closes
        view.sidebarView.clickDisclosure(line: t)   // opens again: known? no — asks now
        await settle { !source.foldersAsked.isEmpty }
        #expect(source.foldersAsked == [url("/Volumes/T")])
    }

    @Test func tabMovesKeys() async {
        let source = source()
        let (view, window) = await make(source)
        window.makeFirstResponder(view.browser)
        view.browser.keyDown(with: keyEvent(code: 48, chars: "\t"))
        #expect(window.firstResponder === view.sidebarView)
        view.sidebarView.keyDown(with: keyEvent(code: 48, chars: "\t"))
        #expect(window.firstResponder === view.browser)
    }

    @Test func tabLeavesFieldsAlone() async {
        let source = source()
        let (view, window) = await make(source)
        view.browser.show(.folder(url("/Volumes/T/x")), selecting: nil)
        window.isReleasedWhenClosed = false
        window.toolbar = view.browser.nsToolbar   // the field is the toolbar's
        window.orderFront(nil)
        defer { window.close() }
        await settle { view.browser.toolbar.searchField.window != nil }   // the toolbar puts its items in the window a turn later
        view.browser.toolbar.focusFilter()
        await settle { view.browser.toolbar.searchField.currentEditor() != nil }
        let focused = window.firstResponder
        #expect(focused !== view.browser)
        view.keyDown(with: keyEvent(code: 48, chars: "\t"))
        #expect(window.firstResponder === focused)
        #expect(window.firstResponder !== view.sidebarView)
    }

    @Test func hiddenSidebarGivesWidth() async {
        let source = source()
        let (view, window) = await make(source)
        view.isSidebarVisible = false
        window.makeFirstResponder(view.browser)
        view.browser.keyDown(with: keyEvent(code: 48, chars: "\t"))
        #expect(window.firstResponder === view.browser)
    }

    @Test func toolbarButtonAsksApp() async {
        let source = source()
        let (view, _) = await make(source)
        var asked = 0
        view.onSidebarToggle = { asked += 1 }
        view.toggleSidebar(nil)
        #expect(asked == 1)
        var home = 0
        view.onHome = { home += 1 }
        view.browser.toolbar.clickHome()
        #expect(home == 1)
    }

    @Test func sidebarContentUsesBrowserTopInset() {
        let view = HomeView(source: source())
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.sidebarView.contentTopInset = 0
        view.layout()
        #expect(view.sidebarView.contentTopInset == view.browser.topInset)
        #expect(view.sidebarView.contentTopInset == HomeBrowserView.defaultTopInset)
    }

    /// The sidebar's sections coming again (a slow `sidebar()`, a volume mounted) while the path's folders are being
    /// listed: the replies still fill the tree.
    @Test func sidebarReloadKeepsTreeReplies() async {
        let source = source()
        source.holdsFolders = true
        let (view, _) = await make(source)
        let b = url("/Volumes/T/A/B")
        view.browser.show(.folder(b), selecting: nil)
        source.yield(b, BrowserFixtures.files(2, in: b.path))
        await settle { !source.foldersAsked.isEmpty }
        view.reloadSidebar()
        await settle()
        source.answerFolders([BrowserFixtures.folder("A", in: "/Volumes/T"), BrowserFixtures.folder("Z", in: "/Volumes/T")])
        await settle { view.sidebarView.titles.contains("Z") }
        #expect(view.sidebarView.titles.contains("Z"))
        #expect(source.foldersAsked == [url("/Volumes/T"), url("/Volumes/T/A")])
    }

    /// A folder shown before the sidebar's sections came (Home's first show): once they come, the path's folders are
    /// listed as they would have been.
    @Test func treeFollowsBeforeSidebarLoads() async {
        let source = source()
        let view = HomeView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let b = url("/Volumes/T/A/B")
        view.browser.show(.folder(b), selecting: nil)   // before the sidebar's sections
        source.yield(b, BrowserFixtures.files(2, in: b.path))
        await settle { source.foldersAsked.count == 2 }
        #expect(source.foldersAsked == [url("/Volumes/T"), url("/Volumes/T/A")])
        // A holds B only: one row.
        #expect(view.sidebarView.titles.contains("A › B"))
    }

    /// → on a row the arrows lit (not the browser's current one) opens it and the light stays there.
    @Test func arrowSelectionSurvivesTreeUpdates() async {
        let source = source()
        let (view, window) = await make(source)
        view.browser.show(.source("recent"), selecting: nil)
        window.makeFirstResponder(view.sidebarView)
        _ = view.sidebarView.handleKey(keyEvent(code: 125, chars: ""))   // ↓ to T
        let t = view.sidebarView.titles.firstIndex(of: "T")!
        #expect(view.sidebarView.highlightedLine == t)
        _ = view.sidebarView.handleKey(keyEvent(code: 124, chars: ""))   // → opens T
        #expect(view.sidebarView.highlightedLine == t)
        source.answerFolders([])
        await settle()
        #expect(view.sidebarView.highlightedLine == view.sidebarView.titles.firstIndex(of: "T"))
    }

    /// A follow cut short by a move leaves no row loading.
    @Test func cancelledFollowClearsLoading() async {
        let source = source()
        source.holdsFolders = true
        let (view, _) = await make(source)
        let b = url("/Volumes/T/A/B")
        view.browser.show(.folder(b), selecting: nil)
        source.yield(b, BrowserFixtures.files(2, in: b.path))
        await settle { !source.foldersAsked.isEmpty }
        view.browser.show(.source("recent"), selecting: nil)
        source.answerFolders([])
        await settle()
        #expect(!view.loadingFolders.contains("/Volumes/T"))
    }

    /// The source hears each move from one location to another (to let a folder's work go).
    @Test func movesAreReportedToTheSource() async {
        let source = source()
        let (view, _) = await make(source)
        let x = url("/Volumes/T/x")
        view.browser.show(.folder(x), selecting: nil)
        view.browser.show(.source("recent"), selecting: nil)
        view.browser.reload()
        view.browser.show(.source("stash"), selecting: nil)
        #expect(source.moves.map(\.1) == [.folder(x), .source("recent"), .source("stash")])
        #expect(source.moves.last?.0 == .source("recent"))
    }

    /// The app's width is kept within the range; the browser starts where the sidebar ends.
    /// Parked (hidden in its window while the app's viewer shows): the sidebar item is collapsed, the app is not
    /// asked to toggle anything and the kept visibility stays; unparked, the sidebar is back as it was, or stays
    /// collapsed if it was hidden meanwhile.
    @Test func parkedCollapsesTheSidebarWithoutAsking() async {
        let (view, _) = await make(source())
        var asked = 0
        view.onSidebarToggle = { asked += 1 }
        let item = view.splitController.splitViewItems[0]
        view.isParked = true
        #expect(item.isCollapsed)
        #expect(view.isSidebarVisible)
        view.isParked = false
        #expect(!item.isCollapsed)
        view.isParked = true
        view.isSidebarVisible = false
        #expect(item.isCollapsed)
        view.isParked = false
        #expect(item.isCollapsed)
        #expect(asked == 0)
    }

    /// The window resized while Home is hidden: the cards are not laid out for it until Home shows again.
    @Test func hiddenBrowserTilesWhenShown() async {
        let (view, window) = await make(source())
        let width = view.browser.gridWidth
        view.isHidden = true
        window.setContentSize(CGSize(width: 900, height: 800))
        view.layoutSubtreeIfNeeded()
        #expect(view.browser.gridWidth == width)
        view.isHidden = false
        view.layoutSubtreeIfNeeded()
        #expect(view.browser.gridWidth != width)
    }

    @Test func sidebarWidthIsSetAndClamped() async {
        let (view, _) = await make(source())
        view.sidebarWidth = 300
        #expect(view.sidebarWidth == 300)
        view.sidebarWidth = 5000
        #expect(view.sidebarWidth == HomeSidebar.widthRange.upperBound)
        view.sidebarWidth = 10
        #expect(view.sidebarWidth == HomeSidebar.widthRange.lowerBound)
    }

    /// The sidebar's row menus are the source's (`HomeSource.sidebarMenu(for:)`), the choice goes back to it.
    @Test func sidebarMenuIsTheSources() {
        let source = FakeHomeSource()
        let view = HomeView(source: source)
        let folder = HomeSidebarRow(id: "/Volumes/T", title: "T", symbol: "externaldrive",
                                    location: .folder(URL(fileURLWithPath: "/Volumes/T", isDirectory: true)))
        let recent = HomeSidebarRow(id: "recent", title: "Recent", symbol: "clock", location: .source("recent"))
        #expect(view.sidebarView.menuItems?(folder) == source.menuItems)
        #expect(view.sidebarView.menuItems?(recent) == [])
        view.sidebarView.onMenu?("reveal", folder)
        #expect(source.sidebarPerformed.map(\.0) == ["reveal"] && source.sidebarPerformed.map(\.1) == ["/Volumes/T"])
    }

    /// The browser's complete listing of the folder on screen is its node's children in the tree at once: opened, it
    /// shows them without a `folders(in:)` of its own.
    @Test func listingCompleteFillsTheFolderItself() async {
        let source = source()
        let (view, _) = await make(source)
        let b = url("/Volumes/T/A/B")
        view.browser.show(.folder(b), selecting: nil)
        source.yield(b, [BrowserFixtures.folder("C", in: b.path), BrowserFixtures.folder("D", in: b.path)]
                        + BrowserFixtures.files(2, in: b.path))
        await settle { view.browser.hasCompleteListing }
        let row = view.sidebarView.titles.firstIndex { $0.hasSuffix("B") }!
        view.sidebarView.clickDisclosure(line: row)
        await settle { view.sidebarView.titles.contains("D") }
        #expect(view.sidebarView.titles.contains("C"))
        #expect(!source.foldersAsked.contains(b))
    }

    /// Back to the parent within a second of opening a subfolder (its listing cut short, the tree showing it with the
    /// path's row alone): its complete listing fills it.
    @Test func backWithinASecondListsTheOpenFolder() async {
        let source = source()
        source.holdsFolders = true
        let (view, _) = await make(source)
        let a = url("/Volumes/T/A"), b = url("/Volumes/T/A/B")
        view.browser.show(.folder(a), selecting: nil)
        view.browser.show(.folder(b), selecting: nil)
        view.browser.goBack()
        #expect(view.browser.location == .folder(a))
        source.yield(a, ["B", "C", "D"].map { BrowserFixtures.folder($0, in: a.path) })
        await settle { view.sidebarView.titles.contains("D") }
        #expect(view.sidebarView.titles.contains("C"))
    }

    /// A share's error from `folders(in:)`: the row stops spinning and is not taken as listed (empty): opened again,
    /// it is asked again.
    @Test func failedFolderListingIsAskedAgain() async {
        let source = source()
        source.folderErrors = ["/Volumes/T"]
        let (view, _) = await make(source)
        let t = view.sidebarView.titles.firstIndex(of: "T")!
        view.sidebarView.clickDisclosure(line: t)
        await settle { source.foldersAsked.count == 1 }
        await settle { view.loadingFolders.isEmpty }
        #expect(view.loadingFolders.isEmpty)
        source.folderErrors = []
        source.folderReplies["/Volumes/T"] = [BrowserFixtures.folder("A", in: "/Volumes/T")]
        view.sidebarView.clickDisclosure(line: t)   // closes
        view.sidebarView.clickDisclosure(line: t)   // opens: asked again
        await settle { view.sidebarView.titles.contains("A") }
        #expect(source.foldersAsked.count == 2)
    }
}
