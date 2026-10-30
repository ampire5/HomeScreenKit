import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeToolbarControllerTests {
    private let a = URL(fileURLWithPath: "/Volumes/T/a")
    private let b = URL(fileURLWithPath: "/Volumes/T/b")

    /// A window the toolbar can be given to. NSToolbar makes its items when a window takes it; the window is never
    /// ordered in, which is enough for `items`.
    private func attach(_ controller: HomeToolbarController) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 400),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.toolbarStyle = .unified
        window.toolbar = controller.nsToolbar
        return window
    }

    @Test func buildsTheBrowserLayout() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        #expect(controller.nsToolbar.items.map(\.itemIdentifier) == HomeToolbarItem.browserOrder)
        #expect(controller.nsToolbar.identifier == "home.browser")
        #expect(!controller.nsToolbar.allowsUserCustomization)
        withExtendedLifetime(window) {}
    }

    @Test func locationTextUpdatesInItsToolbarItem() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        controller.show(title: "Library")
        controller.show(subtitle: "16–19 Sep 2026")
        #expect(controller.windowTitle == "Library")
        #expect(controller.subtitleText == "16–19 Sep 2026")
        #expect(controller.nsToolbar.items[1].itemIdentifier == .toggleSidebar)
        #expect(controller.nsToolbar.items[6].itemIdentifier == HomeToolbarItem.title.identifier)   // after the buttons
        #expect(controller.nsToolbar.centeredItemIdentifiers == [HomeToolbarItem.filter.identifier])
        withExtendedLifetime(window) {}
    }

    /// The title takes the room up to its whole text and gives it back down to 150 pt before an item overflows.
    @available(macOS, deprecated: 12.0)
    @Test func titleItemIsFlexibleUpToItsText() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        let item = controller.nsToolbar.items.first { $0.itemIdentifier == HomeToolbarItem.title.identifier }!
        controller.show(title: "a")
        #expect(item.minSize.width == 150 && item.maxSize.width == 150)
        controller.show(title: String(repeating: "A long folder name ", count: 8))
        #expect(item.minSize.width == 150)
        #expect(item.maxSize.width > 600)
        withExtendedLifetime(window) {}
    }

    @Test func everyItemHasALabelAndATip() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        let systemItems: Set<NSToolbarItem.Identifier> = [.toggleSidebar, .sidebarTrackingSeparator]
        let items = controller.nsToolbar.items.filter {
            $0.itemIdentifier != .flexibleSpace && !systemItems.contains($0.itemIdentifier)
        }
        #expect(items.count == HomeToolbarItem.allCases.count)
        for item in items {
            #expect(!item.label.isEmpty, "\(item.itemIdentifier.rawValue) has no label")
            #expect(item.toolTip?.isEmpty == false, "\(item.itemIdentifier.rawValue) has no tip")
        }
        withExtendedLifetime(window) {}
    }

    @Test func itemsCarryTheHidePriorities() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        for item in controller.nsToolbar.items where item.itemIdentifier != .flexibleSpace
            && item.itemIdentifier != .toggleSidebar && item.itemIdentifier != .sidebarTrackingSeparator {
            // `NSSearchToolbarItem` ignores a priority it is given and keeps 1001 (probed on macOS 26.7).
            if item.itemIdentifier == HomeToolbarItem.search.identifier { continue }
            let wanted = HomeToolbarItem.allCases.first { $0.identifier == item.itemIdentifier }!.priority
            #expect(item.visibilityPriority.rawValue == wanted, "\(item.itemIdentifier.rawValue)")
        }
        withExtendedLifetime(window) {}
    }

    @Test func filterGroupListsAndSelectsTheKinds() {
        let controller = HomeToolbarController()
        var kinds: [BrowserKindFilter] = []
        controller.onKind = { kinds.append($0) }
        #expect(controller.kindTitles == ["All", "Folders", "Photos"])
        controller.show(filter: .photos, visible: true)
        #expect(controller.kindSelection == 2)
        #expect(controller.isFilterControlVisible && controller.filterSelection == 2)
        controller.clickKind(1)
        #expect(controller.filterSelection == 1)
        #expect(kinds == [.folders])
    }

    @Test func pageFiltersReplaceTheKindFilter() {
        let controller = HomeToolbarController()
        var kinds: [BrowserKindFilter] = [], pages: [Int] = []
        controller.onKind = { kinds.append($0) }
        controller.onPageFilter = { pages.append($0) }
        controller.show(pageFilters: ["Scenes", "Images"], selected: 0)
        #expect(controller.kindTitles == ["Scenes", "Images"])
        #expect(controller.isFilterVisible)
        #expect(controller.kindSelection == 0)
        #expect(controller.isFilterControlVisible && controller.filterSelection == 0)
        controller.clickKind(1)
        #expect(pages == [1] && kinds.isEmpty)
        controller.show(pageFilters: ["Scenes", "Images", "Galleries"], selected: 2)
        #expect(controller.kindTitles == ["Scenes", "Images", "Galleries"])
        #expect(controller.kindSelection == 2)
        #expect(controller.filterSelection == 2)
        controller.show(pageFilters: [], selected: nil)
        #expect(controller.kindTitles == ["All", "Folders", "Photos"])
        controller.clickKind(0)
        #expect(kinds == [.all])
    }

    @Test func pageFiltersWorkOnceTheToolbarIsInAWindow() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        controller.show(pageFilters: ["Scenes", "Images"], selected: 1)
        #expect(controller.kindTitles == ["Scenes", "Images"])
        #expect(controller.kindSelection == 1)
        #expect(controller.nsToolbar.items.map(\.itemIdentifier) == HomeToolbarItem.browserOrder)
        withExtendedLifetime(window) {}
    }

    @Test func cardSwitchIsOnlyForFolders() {
        let controller = HomeToolbarController()
        controller.show(cardStyle: .list, visible: false)
        #expect(!controller.isCardSwitchVisible)
        controller.show(cardStyle: .list, visible: true)
        #expect(controller.isCardSwitchVisible)
        #expect(controller.cardSwitchSelection == 2)
        var styles: [CardStyle] = []
        controller.onCardStyle = { styles.append($0) }
        controller.clickCardStyle(1)
        #expect(styles == [.cards])
    }

    @Test func controlsOffOnAPage() {
        let controller = HomeToolbarController()
        controller.show(cardStyle: .posters, visible: true)
        controller.show(controls: false)
        #expect(!controller.isStyleVisible && !controller.isZoomVisible && !controller.isSearchVisible && !controller.isCardSwitchVisible)
        controller.show(controls: true)
        #expect(controller.isStyleVisible && controller.isZoomVisible && controller.isSearchVisible && controller.isCardSwitchVisible)
        controller.show(cardStyle: .posters, visible: false)
        controller.show(controls: false)
        controller.show(controls: true)
        #expect(!controller.isCardSwitchVisible)
    }

    @Test func historyAndZoomCallTheirCallbacks() {
        let controller = HomeToolbarController()
        var log: [String] = []
        controller.onBack = { log.append("back") }
        controller.onForward = { log.append("forward") }
        controller.onUp = { log.append("up") }
        controller.onZoom = { log.append($0 == .smallerSize ? "smaller" : $0 == .largerSize ? "larger" : "\($0)") }
        controller.onHome = { log.append("home") }
        controller.clickHistory(0)
        controller.clickHistory(1)
        controller.clickHistory(2)
        controller.clickZoom(0)
        controller.clickZoom(1)
        controller.clickHome()
        #expect(log == ["back", "forward", "up", "smaller", "larger", "home"])
    }

    /// The slider sends a size, and only a new one; showing a size moves it without sending.
    @Test func zoomSliderSendsItsSize() {
        let controller = HomeToolbarController()
        var sent: [HomeResize] = []
        controller.onZoom = { sent.append($0) }
        controller.show(cardSize: 160, range: 60...480)
        #expect(abs(controller.zoomSliderSize - 160) < 0.5)
        controller.dragZoomSlider(to: 200)
        controller.dragZoomSlider(to: 200.2)
        #expect(sent == [.to(200)])
    }

    @Test func upButtonFollowsTheLocation() throws {
        let controller = HomeToolbarController()
        let window = attach(controller)
        let history = try #require(controller.nsToolbar.items.first {
            $0.itemIdentifier == HomeToolbarItem.history.identifier
        } as? NSToolbarItemGroup)
        #expect(history.subitems.count == 3)
        let up = try #require(history.subitems.first { $0.label == "Up" })
        controller.show(path: [("Places", .places), ("a", .folder(a))], canBack: false, canForward: false, canUp: true)
        #expect(up.isEnabled)
        controller.show(path: [("Places", .places)], canBack: true, canForward: false, canUp: false)
        #expect(!up.isEnabled)
        withExtendedLifetime(window) {}
    }

    @Test func navigationFollowsThePath() {
        let controller = HomeToolbarController()
        controller.show(path: [("Places", .places), ("a", .folder(a))], canBack: true, canForward: false, canUp: true)
        #expect(controller.isNavVisible && controller.canBack && !controller.canForward)
        controller.show(title: "Recent")
        #expect(!controller.isNavVisible)
    }

    @Test func windowTextFollowsThePath() {
        let controller = HomeToolbarController()
        var texts: [(String, String)] = []
        controller.onWindowText = { texts.append(($0, $1)) }
        let zipped = "Trips \u{2215} 2025"
        controller.show(path: [("Photos", .folder(a)), (zipped, .folder(b))], canBack: false, canForward: false, canUp: true)
        controller.show(subtitle: "412 photos")
        #expect(texts.last?.0 == zipped && texts.last?.1 == "412 photos")
        #expect(controller.windowTitle.unicodeScalars.contains("\u{2215}"))
        controller.show(title: "Recent")
        #expect(texts.last?.0 == "Recent" && texts.last?.1 == "412 photos")
        controller.show(path: [("Emoji 🌅 مجلد", .folder(a))], canBack: false, canForward: false, canUp: false)
        #expect(texts.last?.0 == "Emoji 🌅 مجلد")
    }

    @Test func stateSurvivesDetach() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        controller.show(filter: .photos, visible: true)
        controller.show(cardStyle: .list, visible: true)
        controller.show(style: .square)
        controller.filterText = "sun"
        window.toolbar = nil
        window.toolbar = controller.nsToolbar
        #expect(controller.kindSelection == 2)
        #expect(controller.cardSwitchSelection == 2)
        #expect(controller.isCardSwitchVisible)
        #expect(controller.isStyleVisible)
        #expect(controller.filterText == "sun")
        #expect(controller.nsToolbar.items.map(\.itemIdentifier) == HomeToolbarItem.browserOrder)
    }

    @Test func twoControllersShareNothing() {
        let first = HomeToolbarController(), second = HomeToolbarController()
        let w1 = attach(first), w2 = attach(second)
        first.show(filter: .photos, visible: true)
        first.filterText = "x"
        #expect(first.kindSelection == 2)
        #expect(second.kindSelection == 0 && second.filterText.isEmpty)
        withExtendedLifetime((w1, w2)) {}
    }

    /// The search field is as wide as Photos' (it would take all the room the window has left otherwise).
    @Test func searchFieldHasAFixedWidth() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        let search = controller.nsToolbar.items.first { $0.itemIdentifier == HomeToolbarItem.search.identifier } as? NSSearchToolbarItem
        #expect(search?.preferredWidthForSearchField == 180)
        withExtendedLifetime(window) {}
    }

    @Test func searchTextAndEscape() {
        let controller = HomeToolbarController()
        var texts: [String] = [], ended = 0
        controller.onFilterText = { texts.append($0) }
        controller.onFilterEnd = { ended += 1 }
        let field = controller.searchField
        field.stringValue = "ab"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(texts == ["ab"])
        let handled = controller.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(handled && field.stringValue.isEmpty)
        #expect(texts == ["ab", ""] && ended == 1)
        #expect(!controller.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }
}
