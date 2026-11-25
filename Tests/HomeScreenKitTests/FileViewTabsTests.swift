import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct FileViewTabsTests {
    @Test func tabStripBackgroundDoesNotPaintOverBrowserOutsideItsBounds() throws {
        let strip = FileTabStrip()
        strip.frame.size = NSSize(width: 80, height: FileTabStrip.height)
        let canvasHeight = Int(FileTabStrip.height) * 3
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: canvasHeight, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        // With clipping disabled AppKit may invalidate a region larger than the tab strip.
        strip.draw(NSRect(x: 0, y: 0, width: 80, height: CGFloat(canvasHeight)))
        NSGraphicsContext.restoreGraphicsState()

        let middle = try #require(bitmap.colorAt(x: 40, y: canvasHeight / 2))
        #expect(middle.alphaComponent == 0)
        let ends = [canvasHeight / 6, canvasHeight * 5 / 6].compactMap { bitmap.colorAt(x: 40, y: $0) }
        #expect(ends.contains { $0.alphaComponent > 0.99 })
    }

    @Test func stripControlsAddReorderAndCloseTabs() throws {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        home.fileTabsEnabled = true
        let strip = try #require(home.fileTabStrip)
        let plus = try #require(strip.subviews.compactMap { $0 as? NSButton }.first)
        home.layoutSubtreeIfNeeded()
        let firstID = try #require(home.selectedFileTabID)
        #expect(plus.frame.width > 0)
        plus.performClick(nil)
        let secondID = try #require(home.selectedFileTabID)
        #expect(secondID != firstID)

        let scroll = try #require(strip.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView as? NSStackView)
        let pair = try #require(stack.arrangedSubviews.last as? NSStackView)
        let tab = try #require(pair.arrangedSubviews.first as? NSButton)
        let moveLeft = try #require(tab.menu?.items.first)
        #expect(tab.frame.width > 0)
        #expect(moveLeft.isEnabled)
        _ = NSApplication.shared.sendAction(try #require(moveLeft.action), to: moveLeft.target, from: moveLeft)
        #expect(home.fileTabSession()?.tabs.map(\.id) == [secondID, firstID])
        #expect(home.selectedFileTabID == secondID)

        let firstPair = try #require(stack.arrangedSubviews.first as? NSStackView)
        let close = try #require(firstPair.arrangedSubviews.last as? NSButton)
        close.performClick(nil)
        #expect(home.selectedFileTabID == firstID)
        #expect(home.fileTabSession() == nil)
    }

    @Test func navigatingInATabPreservesItsControl() throws {
        let strip = FileTabStrip()
        var tab = HomeFileTab(navigation: FileTabNavigation(at: .places))
        strip.show([tab], selected: tab.id)
        let scroll = try #require(strip.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView as? NSStackView)
        let original = try #require((stack.arrangedSubviews.first as? NSStackView)?.arrangedSubviews.first as? NSButton)

        tab.navigation = FileTabNavigation(at: .folder(URL(fileURLWithPath: "/Movies/Edited")))
        strip.show([tab], selected: tab.id)
        let current = (stack.arrangedSubviews.first as? NSStackView)?.arrangedSubviews.first as? NSButton
        #expect(current === original)
        #expect(current?.title == "Edited")
        #expect(current?.state == .on)
    }

    @Test func tabStripKeepsNewTabAndTheOverflowMenuVisibleAtNarrowWidths() throws {
        let strip = FileTabStrip()
        let tabs = (1...8).map { index in
            HomeFileTab(navigation: FileTabNavigation(at: .folder(URL(fileURLWithPath: "/Movies/Folder \(index)"))))
        }
        strip.frame.size = NSSize(width: 300, height: FileTabStrip.height)
        strip.show(tabs, selected: tabs.last?.id)
        strip.layoutSubtreeIfNeeded()

        let buttons = strip.subviews.compactMap { $0 as? NSButton }
        let add = try #require(buttons.first { $0.accessibilityLabel() == "New Tab" })
        let overflow = try #require(buttons.first { $0.accessibilityLabel() == "Show All Tabs" })
        #expect(!add.isHidden && strip.bounds.contains(add.frame))
        #expect(!overflow.isHidden && strip.bounds.contains(overflow.frame))
        let scroll = try #require(strip.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView as? NSStackView)
        let selected = try #require(stack.arrangedSubviews.last)
        #expect(scroll.documentVisibleRect.contains(selected.frame))
    }

    @Test func sessionDecodingRejectsAnUnknownSelectedTab() throws {
        let tab = FileTabSession.Tab(id: UUID(), folder: nil, selection: nil, anchor: nil)
        let session = FileTabSession(tabs: [tab], selectedID: UUID())
        let data = try JSONEncoder().encode(session)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(FileTabSession.self, from: data) }
    }

    @Test func closingTheParkedTabKeepsRecentOpen() throws {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.fileTabsEnabled = true
        let folder = URL(fileURLWithPath: "/Movies/One", isDirectory: true)
        home.browser.show(.folder(folder), selecting: nil)
        let first = try #require(home.selectedFileTabID)
        home.openFileTab(at: .folder(URL(fileURLWithPath: "/Movies/Two", isDirectory: true)))
        let second = try #require(home.selectedFileTabID)
        home.browser.show(.source("recent"), selecting: nil)
        home.fileTabStrip?.onClose?(second)
        #expect(home.selectedFileTabID == first)
        #expect(home.browser.location == .source("recent"))
        #expect(source.listed.count == 2)
    }

    @Test func closingRestoredFoldersCanSaveAPlacesOnlySession() throws {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.fileTabsEnabled = true
        let places = FileTabSession.Tab(id: UUID(), folder: nil, selection: nil, anchor: nil)
        let folder = FileTabSession.Tab(id: UUID(), folder: URL(fileURLWithPath: "/Movies/One", isDirectory: true),
                                        selection: nil, anchor: nil)
        home.restoreFileTabSession(FileTabSession(tabs: [places, folder], selectedID: folder.id))
        home.fileTabStrip?.onClose?(folder.id)
        let kept = try #require(home.fileTabSession())
        #expect(kept.tabs == [places])
        #expect(kept.selectedID == places.id)
    }

    @Test func restoringAndParkingFileTabsOnlyListsTheActiveFolder() throws {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.fileTabsEnabled = true
        let first = FileTabSession.Tab(id: UUID(), folder: URL(fileURLWithPath: "/Movies/One", isDirectory: true),
                                       selection: nil, anchor: nil)
        let second = FileTabSession.Tab(id: UUID(), folder: URL(fileURLWithPath: "/Volumes/Offline/Two", isDirectory: true),
                                        selection: nil, anchor: nil)
        let saved = FileTabSession(tabs: [first, second], selectedID: first.id)
        let decoded = try JSONDecoder().decode(FileTabSession.self, from: JSONEncoder().encode(saved))
        home.restoreFileTabSession(decoded)
        let firstFolder = try #require(first.folder)
        let secondFolder = try #require(second.folder)
        #expect(source.listed == [firstFolder])
        home.browser.show(.source("recent"), selecting: nil)
        #expect(home.fileTabSession() == saved)
        #expect(source.listed == [firstFolder])
        #expect(home.selectFileTab(second.id))
        #expect(source.listed == [firstFolder, secondFolder])
        #expect(home.browser.location == .folder(secondFolder))
        #expect(!home.browser.history.canGoBack)
    }

    @Test func tabsAtTheSameFolderKeepIndependentHistorySelectionAndScroll() async throws {
        let source = FakeHomeSource()
        let folder = URL(fileURLWithPath: "/Volumes/Test/Videos", isDirectory: true)
        let other = folder.appendingPathComponent("Other", isDirectory: true)
        let entries = BrowserFixtures.files(500)
        source.kept[.folder(folder)] = BrowserListing(entries: entries, complete: true)
        let view = HomeView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.fileTabsEnabled = true
        view.browser.show(.folder(other), selecting: nil)
        view.browser.show(.folder(folder), selecting: entries[30].id)
        await settle(seconds: 5) { view.browser.entries.count == 500 }
        view.layoutSubtreeIfNeeded()
        view.browser.scrollGrid(to: 650)
        let anchor = try #require(view.browser.anchor)
        let first = try #require(view.selectedFileTabID)

        view.openFileTab(at: .folder(folder))
        let second = try #require(view.selectedFileTabID)
        #expect(second != first)
        #expect(!view.browser.history.canGoBack)
        await settle(seconds: 5) { view.browser.entries.count == 500 }
        #expect(view.browser.scrollOffset == 0)

        #expect(view.selectFileTab(first))
        await settle(seconds: 5) { view.browser.entries.count == 500 }
        #expect(view.browser.anchor == anchor)
        #expect(view.browser.selection == entries[30].id)
        view.browser.goBack()
        #expect(view.browser.location == .folder(other))
    }
}
