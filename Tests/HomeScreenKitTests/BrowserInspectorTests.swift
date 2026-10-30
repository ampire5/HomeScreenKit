import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct BrowserInspectorTests {
    @Test func explicitSelectionSurvivesHoverAndMovesByClickAndKeys() async throws {
        let source = FakeHomeSource()
        let folder = URL(fileURLWithPath: "/Examples")
        let files = ["a.jpg", "b.jpg", "c.jpg"].map { BrowserEntry(url: folder.appendingPathComponent($0), name: $0, kind: .file) }
        let browser = HomeBrowserView(source: source)
        browser.selectsOnHover = false
        browser.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        browser.show(.folder(folder), selecting: nil)
        await settle { source.listed.contains(folder) }
        source.yield(folder, files)
        await settle { browser.selectedEntry != nil }
        browser.layoutSubtreeIfNeeded()
        var changes: [String?] = []
        browser.onSelectionChange = { changes.append($0?.id) }
        let a = try #require(browser.card(for: files[0].id) as? PhotoCard)
        let b = try #require(browser.card(for: files[1].id) as? PhotoCard)
        let c = try #require(browser.card(for: files[2].id) as? PhotoCard)
        let hover = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        b.mouseEntered(with: hover)
        #expect(b.isHovered)
        #expect(browser.selectedEntry?.id == files[0].id)
        #expect(a.isSelected && !b.isSelected)
        #expect(!a.ring.isHidden && b.ring.isHidden)
        #expect(changes.isEmpty)
        let point = b.convert(NSPoint(x: b.bounds.midX, y: b.bounds.midY), to: nil)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        b.mouseUp(with: click)
        #expect(browser.selectedEntry?.id == files[1].id)
        #expect(!a.isSelected && b.isSelected)
        #expect(changes == [files[1].id])
        c.mouseEntered(with: hover)
        #expect(browser.selectedEntry?.id == files[1].id)
        #expect(changes == [files[1].id])
        browser.keyDown(with: keyEvent(code: 124, chars: ""))
        #expect(browser.selectedEntry?.id == files[2].id)
        #expect(changes == [files[1].id, files[2].id])
    }

    @Test func explicitClickCancelsASelectionStillWaitingForItsRestoredFile() async throws {
        for contextMenu in [false, true] {
            let source = FakeHomeSource()
            let folder = URL(fileURLWithPath: "/Examples")
            let files = ["a.jpg", "b.jpg", "c.jpg"].map { BrowserEntry(url: folder.appendingPathComponent($0), name: $0, kind: .file) }
            let browser = HomeBrowserView(source: source)
            browser.selectsOnHover = false
            browser.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
            browser.show(.folder(folder), selecting: files[2].id)
            await settle { source.listed.contains(folder) }
            source.yieldPartial(folder, Array(files.prefix(2)))
            await settle { browser.entries.count == 2 }
            browser.layoutSubtreeIfNeeded()
            let card = try #require(browser.card(for: files[1].id))
            let point = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)
            let click = try #require(NSEvent.mouseEvent(with: contextMenu ? .rightMouseDown : .leftMouseUp,
                location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            if contextMenu { #expect(card.menu(for: click) != nil) }
            else { card.mouseUp(with: click) }
            #expect(browser.selectedEntry?.id == files[1].id)
            source.yield(folder, files)
            await settle { browser.hasCompleteListing && browser.entries.count == 3 }
            #expect(browser.selectedEntry?.id == files[1].id)
        }
    }

    @Test func contextMenuRequestIsExplicitSelectionEvenWithoutHoverSelection() async throws {
        let source = FakeHomeSource()
        let folder = URL(fileURLWithPath: "/Examples")
        let files = ["cat.jpg", "dog.jpg"].map { BrowserEntry(url: folder.appendingPathComponent($0), name: $0, kind: .file) }
        let browser = HomeBrowserView(source: source)
        browser.selectsOnHover = false
        browser.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        browser.show(.folder(folder), selecting: nil)
        await settle { source.listed.contains(folder) }
        source.yield(folder, files)
        await settle { browser.selectedEntry != nil }
        browser.layoutSubtreeIfNeeded()
        let card = try #require(browser.card(for: files[1].id))
        let click = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(card.menu(for: click) != nil)
        #expect(browser.selectedEntry?.id == files[1].id)
    }

    @Test func hiddenInspectorFactoryWaitsForFirstRequestAndIsRetained() {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        var creations = 0
        let controller = NSViewController()
        controller.view = NSView()
        home.configureInspector(width: 340) { creations += 1; return controller }
        home.layoutSubtreeIfNeeded()
        home.isParked = true
        home.isParked = false
        home.layoutSubtreeIfNeeded()
        #expect(creations == 0)
        #expect(home.splitController.splitViewItems.count == 2)
        #expect(home.browser.toolbar.onInspector != nil)
        home.browser.toolbar.onInspector?()
        home.layoutSubtreeIfNeeded()
        #expect(creations == 1)
        #expect(home.isInspectorVisible)
        #expect(home.splitController.splitViewItems.count == 3)
        #expect(home.splitController.splitViewItems.last?.viewController === controller)
        home.isInspectorVisible = false
        home.isInspectorVisible = true
        home.isParked = true
        home.isParked = false
        #expect(creations == 1)
        #expect(home.splitController.splitViewItems.last?.viewController === controller)
    }

    @Test func parkedVisibilityIntentWaitsUntilUnparkAndCanBeCancelled() {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.isParked = true
        var creations = 0
        home.configureInspector { creations += 1; let c = NSViewController(); c.view = NSView(); return c }
        home.isInspectorVisible = true
        #expect(creations == 0)
        home.isInspectorVisible = false
        home.isParked = false
        #expect(creations == 0)
        home.isParked = true
        home.isInspectorVisible = true
        home.isParked = false
        #expect(creations == 1)
        #expect(home.splitController.splitViewItems.last?.isCollapsed == false)
    }

    @Test func factorySeesLatestSelectionInsteadOfTheSelectionAtRegistration() async {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let folder = URL(fileURLWithPath: "/Examples")
        let files = ["cat.jpg", "dog.jpg"].map { BrowserEntry(url: folder.appendingPathComponent($0), name: $0, kind: .file) }
        var selectedAtCreation: String?
        home.configureInspector { [weak home] in
            selectedAtCreation = home?.browser.selectedEntry?.name
            let c = NSViewController(); c.view = NSView(); return c
        }
        home.browser.show(.folder(folder), selecting: nil)
        await settle { source.listed.contains(folder) }
        source.yield(folder, files)
        await settle { home.browser.selectedEntry != nil }
        home.browser.select(id: files[1].id)
        #expect(selectedAtCreation == nil)
        home.isInspectorVisible = true
        #expect(selectedAtCreation == "dog.jpg")
    }

    @Test func selectedEntryTracksListingAndClearsOnNavigation() async {
        let source = FakeHomeSource()
        let folder = URL(fileURLWithPath: "/Examples")
        let a = BrowserEntry(url: folder.appendingPathComponent("cat.jpg"), name: "cat.jpg", kind: .file)
        let b = BrowserEntry(url: folder.appendingPathComponent("dog.jpg"), name: "dog.jpg", kind: .file)
        let browser = HomeBrowserView(source: source)
        browser.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        var changes: [BrowserEntry?] = []
        browser.onSelectionChange = { changes.append($0) }
        browser.show(.folder(folder), selecting: nil)
        await settle { source.listed.contains(folder) }
        source.yield(folder, [a, b])
        await settle { browser.selectedEntry == a }
        browser.select(id: b.id)
        #expect(changes.last! == b)
        let count = changes.count
        browser.select(id: b.id)
        #expect(changes.count == count)
        var updated = b
        updated.size = 2048
        source.yield(folder, [a, updated])
        await settle { browser.selectedEntry?.size == 2048 }
        #expect(changes.last!?.size == 2048)
        source.yield(folder, [])
        await settle { browser.entries.isEmpty }
        #expect(browser.selectedEntry == nil)
        #expect(changes.last! == nil)
    }

    @Test func selectedFactsArrivingAfterTheListingReachTheInspector() async {
        let source = FakeHomeSource()
        let folder = URL(fileURLWithPath: "/Examples")
        let entry = BrowserEntry(url: folder.appendingPathComponent("cat.jpg"), name: "cat.jpg", kind: .file)
        let browser = HomeBrowserView(source: source)
        browser.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        var latest: BrowserEntry?
        browser.onSelectionChange = { latest = $0 }
        browser.show(.folder(folder), selecting: nil)
        await settle { source.listed.contains(folder) }
        source.yield(folder, [entry])
        await settle { browser.selectedEntry != nil }
        browser.setFacts([entry.id: FileFacts(width: 6000, height: 4000)])
        #expect(latest?.facts?.width == 6000)
        #expect(browser.selectedEntry?.facts?.height == 4000)
    }

    @Test func nativeDividerCollapseReconcilesVisibility() {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        let controller = NSViewController(); controller.view = NSView()
        home.installInspector(controller)
        home.isInspectorVisible = true
        var visible: Bool?
        home.onInspectorVisibilityChange = { visible = $0 }
        home.splitController.splitViewItems.last?.isCollapsed = true
        #expect(!home.isInspectorVisible)
        #expect(visible == false)
        home.splitController.splitViewItems.last?.isCollapsed = false
        #expect(home.isInspectorVisible)
        #expect(visible == true)
    }

    @Test func inspectorIsOptionalAndParkedWithoutLosingItsState() {
        let source = FakeHomeSource()
        let home = HomeView(source: source)
        home.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        #expect(!home.isInspectorVisible)
        let controller = NSViewController()
        controller.view = NSView()
        home.installInspector(controller, width: 320)
        #expect(!home.isInspectorVisible)
        home.isInspectorVisible = true
        home.layoutSubtreeIfNeeded()
        #expect(controller.view.superview != nil)
        let identity = controller.view
        home.isParked = true
        #expect(home.isInspectorVisible)
        #expect(home.splitController.splitViewItems.last?.isCollapsed == true)
        home.isParked = false
        #expect(home.splitController.splitViewItems.last?.isCollapsed == false)
        #expect(controller.view === identity)
        home.isInspectorVisible = false
        #expect(home.splitController.splitViewItems.last?.isCollapsed == true)
    }
}
