import AppKit
import Testing
@testable import HomeScreenKit

@MainActor @Suite struct HomeBrowserLayoutTests {
    @Test func unchangedToolbarInsetDoesNotScheduleAnotherLayoutWithoutCustomPage() {
        let source = FakeHomeSource()
        let browser = HomeBrowserView(source: source)
        browser.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        browser.layoutSubtreeIfNeeded()
        browser.needsLayout = false
        browser.layout()
        #expect(!browser.needsLayout)
    }
}
