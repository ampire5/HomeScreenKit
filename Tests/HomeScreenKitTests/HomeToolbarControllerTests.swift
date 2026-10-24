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

    @Test func everyItemHasALabelAndATip() {
        let controller = HomeToolbarController()
        let window = attach(controller)
        let items = controller.nsToolbar.items.filter { $0.itemIdentifier != .flexibleSpace }
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
        for item in controller.nsToolbar.items where item.itemIdentifier != .flexibleSpace {
            // `NSSearchToolbarItem` ignores a priority it is given and keeps 1001 (probed on macOS 26.7).
            if item.itemIdentifier == HomeToolbarItem.search.identifier { continue }
            let wanted = HomeToolbarItem.allCases.first { $0.identifier == item.itemIdentifier }!.priority
            #expect(item.visibilityPriority.rawValue == wanted, "\(item.itemIdentifier.rawValue)")
        }
        withExtendedLifetime(window) {}
    }

    @Test func kindSegmentsAreTheFilterTitles() {
        let controller = HomeToolbarController()
        var kinds: [BrowserKindFilter] = []
        controller.onKind = { kinds.append($0) }
        #expect(controller.kindTitles == ["All", "Folders", "Photos"])
        controller.show(filter: .photos, visible: true)
        #expect(controller.kindSelection == 2)
        controller.clickKind(1)
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
        controller.clickKind(1)
        #expect(pages == [1] && kinds.isEmpty)
        controller.show(pageFilters: ["Scenes", "Images", "Galleries"], selected: 2)
        #expect(controller.kindTitles == ["Scenes", "Images", "Galleries"])
        #expect(controller.kindSelection == 2)
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
        #expect(!controller.isZoomVisible && !controller.isSearchVisible && !controller.isCardSwitchVisible)
        controller.show(controls: true)
        #expect(controller.isZoomVisible && controller.isSearchVisible && controller.isCardSwitchVisible)
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
        controller.onZoom = { log.append($0 == .smaller ? "smaller" : "larger") }
        controller.onSidebar = { log.append("sidebar") }
        controller.onHome = { log.append("home") }
        controller.clickHistory(0)
        controller.clickHistory(1)
        controller.clickZoom(0)
        controller.clickZoom(1)
        controller.clickSidebar()
        controller.clickHome()
        #expect(log == ["back", "forward", "smaller", "larger", "sidebar", "home"])
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
        controller.filterText = "sun"
        window.toolbar = nil
        window.toolbar = controller.nsToolbar
        #expect(controller.kindSelection == 2)
        #expect(controller.cardSwitchSelection == 2)
        #expect(controller.isCardSwitchVisible)
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
