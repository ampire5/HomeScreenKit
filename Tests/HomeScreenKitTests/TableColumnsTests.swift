import AppKit
import Testing
import HomeScreenModel
@testable import HomeScreenKit

@MainActor @Suite struct TableColumnsTests {
    @Test func columnMenuOffersStoredPhotoMetadata() throws {
        let header = ListHeader()
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(header.menu(for: event))
        for title in ["Camera", "Lens", "ISO", "Date Taken", "Width", "Height"] {
            #expect(menu.items.contains { $0.title == title })
        }
        #expect(menu.items.first { $0.title == "Name" }?.isEnabled == false)
    }
    @Test func enabledColumnsFitWithoutDroppingMetadata() {
        let selected: Set<TableColumn> = [.name, .size, .camera, .lens, .iso, .taken]
        let width = ListColumns.minimumWidth(for: selected, metrics: GridMetrics())
        let columns = ListColumns(width: width, selected: selected)
        for column in selected { #expect(columns[column] != nil) }
        let frames = selected.compactMap { columns[$0] }.sorted { $0.x < $1.x }
        for (left, right) in zip(frames, frames.dropFirst()) {
            #expect(left.x + left.width <= right.x)
        }
    }

    @Test func metadataArrivesAfterARowWasCreated() {
        var item = HomeCardItem(id: "photo", title: "Photo", tooltip: "Photo", symbol: "photo")
        let row = ListRow(item: item)
        row.selectedColumns = [.name, .camera, .iso]
        row.frame = CGRect(x: 0, y: 0, width: 800, height: 44)
        row.layoutSubtreeIfNeeded()
        #expect(TableColumn.camera.text(for: item).isEmpty)
        item.facts = FileFacts(camera: "Camera A", iso: 800)
        row.show(item)
        row.layoutSubtreeIfNeeded()
        let strings = row.subviews.compactMap { ($0 as? CardText)?.stringValue }
        #expect(strings.contains("Camera A") && strings.contains("800"))
        item.facts = nil
        row.show(item)
        let cleared = row.subviews.compactMap { ($0 as? CardText)?.stringValue }
        #expect(!cleared.contains("Camera A"))
    }

    @Test func togglingColumnsKeepsNameAndCallsTheBrowser() throws {
        let header = ListHeader()
        var chosen: Set<TableColumn>?
        header.onColumns = { chosen = $0 }
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(header.menu(for: event))
        let iso = try #require(menu.items.first { $0.title == "ISO" })
        menu.performActionForItem(at: menu.index(of: iso))
        #expect(chosen?.contains(.iso) == true && chosen?.contains(.name) == true)
        let reset = try #require(menu.items.first { $0.title == "Default Columns" })
        menu.performActionForItem(at: menu.index(of: reset))
        #expect(chosen == TableColumn.standard)
    }

    @Test func tableWindowBenchAndPreview() async throws {
        guard ProcessInfo.processInfo.environment["HOMESCREEN_TABLE_BENCH"] == "1" else { return }
        let source = FakeHomeSource()
        let folder = URL(fileURLWithPath: "/Demo/Photos")
        source.cardStyles[.folder(folder)] = .list
        let browser = HomeBrowserView(source: source)
        browser.tableColumns = TableColumn.standard
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 760),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = browser
        window.toolbar = browser.nsToolbar
        window.orderFront(nil)
        browser.show(.folder(folder), selecting: nil)
        var entries = BrowserFixtures.files(2000)
        for i in entries.indices {
            entries[i].facts = FileFacts(width: 6000, height: 4000, camera: "Camera A", lens: "24–70 mm", exposure: 1/250,
                aperture: 2.8, iso: 400, focalLength: 50)
        }
        source.yield(folder, entries, complete: true)
        await settle(seconds: 5) { browser.entries.count == 2000 }
        func cpu() -> Double {
            var t = timespec(); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
            return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1_000_000
        }
        var samples: [(Double, Double, Double)] = []
        for _ in 0..<10 {
            let start = cpu()
            browser.tableColumns = [.name, .size, .width, .height, .camera, .lens, .shutter, .aperture, .iso]
            browser.tile(); browser.layoutSubtreeIfNeeded()
            let expanded = cpu()
            browser.tableColumns = Set(TableColumn.allCases)
            browser.tile(); browser.layoutSubtreeIfNeeded()
            let all = cpu()
            browser.tableColumns = TableColumn.standard
            browser.tile(); browser.layoutSubtreeIfNeeded()
            let normal = cpu()
            samples.append((expanded-start, all-expanded, normal-all))
            await settle()
        }
        print("TABLE_BENCH ms (expanded, all, default): \(samples)")
        browser.tableColumns = [.name, .size, .width, .height, .camera, .lens, .shutter, .aperture, .iso]
        browser.tile(); browser.layoutSubtreeIfNeeded()
        if let bitmap = browser.bitmapImageRepForCachingDisplay(in: browser.bounds) {
            browser.cacheDisplay(in: browser.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/loupe-table-preview.png"))
        }
    }

}
