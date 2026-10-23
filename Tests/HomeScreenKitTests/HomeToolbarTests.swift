import AppKit
import Testing
@testable import HomeChrome
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct HomeToolbarTests {
    private let x = URL(fileURLWithPath: "/Volumes/T/x")

    private func toolbar() -> HomeToolbar {
        let bar = HomeToolbar()
        bar.frame = CGRect(x: 0, y: 0, width: 1200, height: HomeToolbar.height)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    @Test func crumbsLastBold() {
        let bar = toolbar()
        bar.show(path: [("Places", .places), ("T", .folder(x.deletingLastPathComponent())), ("x", .folder(x))],
                 canBack: true, canForward: false, canUp: true)
        #expect(bar.crumbTitles == ["Places", "T", "x"])
        #expect(bar.crumbFonts.last?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(bar.crumbFonts.first?.fontDescriptor.symbolicTraits.contains(.bold) == false)
        var went: [BrowserLocation] = []
        bar.onCrumb = { went.append($0) }
        bar.clickCrumb(1)
        #expect(went == [.folder(x.deletingLastPathComponent())])
        bar.show(subtitle: "2 photos")
        #expect(bar.subtitleText == "2 photos")
    }

    @Test func sortTitlesShowDirection() {
        let bar = toolbar()
        bar.show(sort: BrowserSort(key: .date, ascending: false), keys: [.name, .date, .size])
        #expect(bar.sortTitles == ["Name", "Date ↓", "Size"])
        bar.show(sort: BrowserSort(key: .name, ascending: true), keys: [.name, .date, .size])
        #expect(bar.sortTitles == ["Name ↑", "Date", "Size"])
    }

    @Test func sortClickCallsKey() {
        let bar = toolbar()
        var keys: [BrowserSort.Key] = []
        bar.onSortKey = { keys.append($0) }
        bar.clickSort(2)
        bar.clickSort(0)
        #expect(keys == [.size, .name])
    }

    @Test func kindClickCallsBack() {
        let bar = toolbar()
        var kinds: [BrowserKindFilter] = []
        bar.onKind = { kinds.append($0) }
        bar.clickKind(2)
        #expect(kinds == [.photos])
    }

    @Test func filterHiddenOnPlaces() {
        let bar = toolbar()
        bar.show(filter: .all, visible: false)
        #expect(!bar.isFilterVisible)
        bar.show(filter: .folders, visible: true)
        #expect(bar.isFilterVisible)
    }

    @Test func fieldTextCallsBack() {
        let bar = toolbar()
        var texts: [String] = []
        bar.onFilterText = { texts.append($0) }
        bar.field.stringValue = "ab"
        bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.field))
        #expect(texts == ["ab"])
        #expect(bar.filterText == "ab")
    }

    @Test func escapeInFieldEnds() {
        let bar = toolbar()
        var texts: [String] = [], ended = 0
        bar.onFilterText = { texts.append($0) }
        bar.onFilterEnd = { ended += 1 }
        bar.field.stringValue = "ab"
        let handled = bar.control(bar.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(handled)
        #expect(bar.filterText == "")
        #expect(texts == [""])
        #expect(ended == 1)
    }

    @Test func zoomButtonsStep() {
        let bar = toolbar()
        var steps: [HomeResize] = []
        bar.onZoom = { steps.append($0) }
        bar.zoom.press(0)
        bar.zoom.press(1)
        #expect(steps == [.smaller, .larger])
    }

    @Test func styleButtonSymbolFollowsStyle() {
        let bar = toolbar()
        var pressed = 0
        bar.onStyle = { pressed += 1 }
        bar.show(style: .square)
        #expect(bar.styleSymbol == "square.grid.2x2")
        bar.show(style: .aspect)
        #expect(bar.styleSymbol == "rectangle.grid.2x2")
        bar.styleButton.press(0)
        #expect(pressed == 1)
    }

    @Test func siblingArrowCallsBack() {
        let bar = toolbar()
        bar.popUp = { _, _ in }
        bar.show(path: [("Places", .places), ("T", .folder(x.deletingLastPathComponent())), ("x", .folder(x))],
                 canBack: false, canForward: false, canUp: true)
        var asked: [Int] = []
        bar.onSiblings = { asked.append($0) }
        bar.clickSiblings(2)
        #expect(asked == [2])
    }

    @Test func kindCapsuleClearsTheRightGroup() {
        for width: CGFloat in [900, 1100, 1400, 2000] {
            let bar = HomeToolbar()
            bar.frame = CGRect(x: 0, y: 0, width: width, height: HomeToolbar.height)
            bar.show(filter: .all, visible: true)
            bar.layoutSubtreeIfNeeded()
            #expect(bar.kindFrame.maxX <= bar.sortFrame.minX, "width \(width)")
        }
    }

    @Test func sidebarButtonFirst() {
        let bar = toolbar()
        #expect(bar.sidebarButton.frame.maxX <= bar.navFrame.minX)
        var pressed = 0
        bar.onSidebar = { pressed += 1 }
        bar.sidebarButton.press(0)
        #expect(pressed == 1)
    }

    /// The house sits between the sidebar button and ‹ › ↑, and stays with a source's title.
    @Test func homeButtonAfterSidebar() {
        let bar = toolbar()
        #expect(bar.sidebarButton.frame.maxX <= bar.homeButton.frame.minX)
        #expect(bar.homeButton.frame.maxX <= bar.navFrame.minX)
        var pressed = 0
        bar.onHome = { pressed += 1 }
        bar.homeButton.press(0)
        #expect(pressed == 1)
        bar.show(title: "Recent")
        bar.layoutSubtreeIfNeeded()
        #expect(!bar.homeButton.isHidden)
    }

    @Test func titleHidesNav() {
        let bar = toolbar()
        bar.show(title: "Recent")
        #expect(bar.crumbTitles == ["Recent"])
        #expect(!bar.isNavVisible)
        bar.show(path: [("Places", .places), ("x", .folder(x))], canBack: true, canForward: false, canUp: true)
        #expect(bar.isNavVisible)
        #expect(bar.crumbTitles == ["Places", "x"])
    }

    @Test func sortKeysFromSource() {
        let bar = toolbar()
        bar.show(sort: BrowserSort(key: .date, ascending: false), keys: [.date, .name])
        #expect(bar.sortTitles == ["Date ↓", "Name"])
        var keys: [BrowserSort.Key] = []
        bar.onSortKey = { keys.append($0) }
        bar.clickSort(0)
        bar.clickSort(1)
        #expect(keys == [.date, .name])
        bar.show(sort: .standard, keys: [])
        #expect(!bar.isSortVisible)
    }

    @Test func pageFilters() {
        let bar = toolbar()
        bar.show(pageFilters: ["Scenes", "Images", "Galleries"], selected: 2)
        #expect(bar.kindTitles == ["Scenes", "Images", "Galleries"])
        #expect(bar.isFilterVisible)
        var pages: [Int] = [], kinds: [BrowserKindFilter] = []
        bar.onPageFilter = { pages.append($0) }
        bar.onKind = { kinds.append($0) }
        bar.clickKind(0)
        #expect(pages == [0])
        #expect(kinds.isEmpty)
        bar.show(pageFilters: [], selected: nil)
        #expect(bar.kindTitles == ["All", "Folders", "Photos"])
        bar.clickKind(1)
        #expect(kinds == [.folders])
    }

    @Test func pageHidesGridControls() {
        let bar = toolbar()
        bar.show(controls: false)
        #expect(bar.field.isHidden && bar.zoom.isHidden && bar.styleButton.isHidden)
        bar.show(controls: true)
        #expect(!bar.field.isHidden && !bar.zoom.isHidden && !bar.styleButton.isHidden)
    }

    // MARK: Progress pill

    static let running = ThumbsProgressState(fraction: 0.25, text: "Thumbnails 120 / 480", paused: false,
                                             rows: [.init(title: "In view", done: 24, total: 24),
                                                    .init(title: "Rest of folder", done: 96, total: 216),
                                                    .init(title: "Subfolders", done: 0, total: 48)])

    @Test func pillTextAndRingFollowTheState() {
        let pill = ThumbsProgressPill()
        pill.show(Self.running)
        #expect(!pill.isHidden)
        #expect(pill.text == "Thumbnails 120 / 480")
        #expect(pill.ringEnd == 0.25)
        #expect(pill.ringColor == Chrome.Palette.card.accent)
        #expect(pill.glyph == .pause)
        var paused = Self.running
        paused.paused = true
        paused.text = "Paused · 120 / 480"
        paused.fraction = 0.5
        pill.show(paused)
        #expect(pill.text == "Paused · 120 / 480")
        #expect(pill.ringEnd == 0.5)
        #expect(pill.ringColor == Chrome.Palette.progress.pausedRing)
        #expect(pill.glyph == .play)
        // Height 28, 6 before the 20 pt ring, 8 to the text, 12 after it (the board's button).
        let size = pill.intrinsicContentSize
        #expect(size.height == 28)
        #expect(size.width == 6 + 20 + 8 + ceil(pill.textWidth) + 12)
        pill.show(nil)
        #expect(pill.isHidden)
    }

    @Test func pillSitsBesideTheSort() {
        let bar = toolbar()
        bar.frame.size.width = 1400
        #expect(!bar.isProgressVisible)
        bar.show(progress: Self.running)
        bar.layoutSubtreeIfNeeded()
        #expect(bar.isProgressVisible)
        // As on the board: just before the sort capsule, centred on the same line.
        #expect(bar.progressFrame.maxX + 10 == bar.sortFrame.minX)
        #expect(bar.progressFrame.midY == bar.sortFrame.midY)
        bar.show(progress: nil)
        bar.layoutSubtreeIfNeeded()
        #expect(!bar.isProgressVisible)
    }

    @Test func popoverShowsRowsNoteAndButtons() {
        let pill = ThumbsProgressPill()
        var state = Self.running
        state.pauseNote = "Paused while you browse"
        state.paused = true
        pill.show(state)
        let panel = pill.makePanel()
        #expect(panel.title == "Thumbnails")
        #expect(panel.rowTexts == ["In view 24 / 24", "Rest of folder 96 / 216", "Subfolders 0 / 48"])
        #expect(panel.barFractions == [1, 96.0 / 216, 0])
        #expect(panel.note == "Paused while you browse")
        // The viewer's pause leaves the user's button at Pause; the user's own pause turns it to Resume.
        #expect(panel.pauseButton.title == "Pause")
        #expect(panel.prepareButton.title == "Prepare subfolders")
        var pauses: [Bool] = [], prepares = 0
        pill.onPause = { pauses.append($0) }
        pill.onPrepare = { prepares += 1 }
        panel.pauseButton.performClick(nil)
        state.pausedByUser = true
        state.pauseNote = "Paused"
        pill.show(state)
        #expect(panel.pauseButton.title == "Resume")
        #expect(panel.note == "Paused")
        panel.pauseButton.performClick(nil)
        panel.prepareButton.performClick(nil)
        #expect(pauses == [true, false])
        #expect(prepares == 1)
        state.pauseNote = nil
        pill.show(state)
        #expect(panel.note == nil)
    }

    /// Narrowing the window: the full pill, then the ring alone (the text in its tooltip), then none, while the path
    /// keeps its room; the same order with the posters / cards / list switch shown.
    @Test(arguments: [false, true]) func narrowToolbarHidesThePillFirst(cardSwitch: Bool) {
        let bar = toolbar()
        bar.show(path: [("Places", .places), ("x", .folder(x))], canBack: true, canForward: false, canUp: true)
        bar.show(cardStyle: .posters, visible: cardSwitch)
        bar.show(progress: Self.running)
        var steps: [HomeToolbar.ProgressStep] = []
        for width in stride(from: 1800.0, through: 500, by: -10) {
            bar.frame.size.width = width
            bar.layoutSubtreeIfNeeded()
            let step = bar.progressStep
            if steps.last != step { steps.append(step) }
            #expect(bar.isSortVisible && bar.isFilterVisible)
            let path = bar.kindFrame.minX - 10 - (bar.navFrame.maxX + 14)
            switch step {
            case .full:
                #expect(path >= HomeToolbar.pathRoomForFullProgress, "width \(width)")
                #expect(bar.progress.toolTip == nil)
                #expect(bar.progressFrame.width > 28)
            case .compact:
                #expect(path >= HomeToolbar.pathRoomForCompactProgress, "width \(width)")
                #expect(bar.progress.toolTip == "Thumbnails 120 / 480")
                #expect(bar.progressFrame.size == CGSize(width: 28, height: 28))
                #expect(bar.progressFrame.maxX + 10 == bar.sortFrame.minX)
            case .hidden:
                #expect(!bar.isProgressVisible)
            }
        }
        #expect(steps == [.full, .compact, .hidden])
    }

    /// The popover follows its content (the note coming and going, rows added) and closes when a narrow window hides
    /// the pill.
    @Test func popoverFollowsItsContentAndClosesWithThePill() async {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 300), styleMask: [.titled], backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let bar = toolbar()
        bar.frame.size.width = 1400
        window.contentView?.addSubview(bar)
        window.orderFront(nil)
        var state = Self.running
        bar.show(progress: state)
        bar.layoutSubtreeIfNeeded()
        bar.progress.togglePopover()
        await settle { bar.progress.isPopoverShown }
        #expect(bar.progress.isPopoverShown)
        let first = bar.progress.popoverContentSize
        state.pauseNote = "Paused"
        state.pausedByUser = true
        bar.show(progress: state)
        let withNote = bar.progress.popoverContentSize
        #expect(withNote.height > first.height)
        #expect(withNote == bar.progress.panelFittingSize)
        state.rows.append(.init(title: "More", done: 1, total: 2))
        bar.show(progress: state)
        #expect(bar.progress.popoverContentSize.height > withNote.height)
        state.pauseNote = nil
        state.rows.removeLast()
        bar.show(progress: state)
        #expect(bar.progress.popoverContentSize == first)
        bar.frame.size.width = 600
        bar.layoutSubtreeIfNeeded()
        #expect(!bar.isProgressVisible)
        await settle { !bar.progress.isPopoverShown }
        #expect(!bar.progress.isPopoverShown)
    }

    /// The View menu's Thumbnails…: the popover from the pill when it shows, else from the sort (a narrow window), where
    /// it stays open through the toolbar's layout passes; nothing without a state.
    @Test func progressPopoverOpensFromTheSortWhenThePillIsHidden() async {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 300), styleMask: [.titled], backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let bar = toolbar()
        bar.show(path: [("Places", .places), ("x", .folder(x))], canBack: true, canForward: false, canUp: true)
        bar.show(sort: .standard, keys: [.name, .date, .size])
        window.contentView?.addSubview(bar)
        window.orderFront(nil)
        bar.frame.size.width = 1400
        bar.layoutSubtreeIfNeeded()
        bar.show(progress: Self.running)
        bar.layoutSubtreeIfNeeded()
        #expect(bar.showProgressPopover())
        await settle { bar.progress.isPopoverShown }
        #expect(bar.progress.isPopoverShown)
        #expect(bar.progress.isPopoverOnPill)
        bar.progress.closePopover()
        await settle { !bar.progress.isPopoverShown }
        bar.frame.size.width = 600
        bar.layoutSubtreeIfNeeded()
        #expect(!bar.isProgressVisible)
        #expect(bar.showProgressPopover())
        await settle { bar.progress.isPopoverShown }
        #expect(bar.progress.isPopoverShown)
        #expect(!bar.progress.isPopoverOnPill)
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(bar.progress.isPopoverShown)
        // Done: the pill goes out, the popover from the sort stays with the last counts.
        bar.show(progress: nil)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(bar.progress.isPopoverShown)
    }

    /// View › Thumbnails… with nothing being prepared (the pill out): the popover opens from the sort with the counts
    /// the app gave last, zeros before any; it follows them while open and stays when the work is done.
    @Test func progressPopoverOpensWithoutWork() async {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 300), styleMask: [.titled], backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let bar = toolbar()
        bar.show(path: [("Places", .places), ("x", .folder(x))], canBack: true, canForward: false, canUp: true)
        bar.show(sort: .standard, keys: [.name, .date, .size])
        window.contentView?.addSubview(bar)
        window.orderFront(nil)
        bar.frame.size.width = 1400
        bar.layoutSubtreeIfNeeded()
        #expect(!bar.isProgressVisible)
        #expect(bar.showProgressPopover())
        await settle { bar.progress.isPopoverShown }
        #expect(bar.progress.isPopoverShown)
        #expect(!bar.progress.isPopoverOnPill)
        #expect(bar.progress.panelRowTexts == ["In view 0 / 0", "Rest of folder 0 / 0", "Subfolders 0 / 0"])
        var done = Self.running
        done.working = false
        done.rows = [.init(title: "In view", done: 24, total: 24), .init(title: "Rest of folder", done: 216, total: 216),
                     .init(title: "Subfolders", done: 48, total: 48)]
        bar.show(progressDetail: done)
        #expect(bar.progress.panelRowTexts == ["In view 24 / 24", "Rest of folder 216 / 216", "Subfolders 48 / 48"])
        #expect(!bar.isProgressVisible)
        bar.show(progress: nil)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(bar.progress.isPopoverShown)
    }

    /// While a subtree is being prepared the popover's second button stops it.
    @Test func stopPreparingWhileASubtreeRuns() {
        let pill = ThumbsProgressPill()
        var state = Self.running
        state.subtreeRunning = true
        pill.show(state)
        let panel = pill.makePanel()
        #expect(panel.prepareButton.title == "Stop preparing")
        var prepares = 0, stops = 0
        pill.onPrepare = { prepares += 1 }
        pill.onStopSubtree = { stops += 1 }
        panel.prepareButton.performClick(nil)
        #expect(stops == 1 && prepares == 0)
        state.subtreeRunning = false
        pill.show(state)
        #expect(panel.prepareButton.title == "Prepare subfolders")
        panel.prepareButton.performClick(nil)
        #expect(stops == 1 && prepares == 1)
    }
}
