import AppKit
import Testing
import HomeScreenModel
@testable import HomeScreenKit

@MainActor @Suite struct MediaColumnAvailabilityTests {
    @Test func photoColumnMenuExcludesVideoFacts() throws {
        let header = ListHeader()
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let titles = try #require(header.menu(for: event)).items.map(\.title)
        for title in ["Duration", "Codec", "Frame Rate", "Bitrate", "Dynamic Range"] {
            #expect(!titles.contains(title))
        }
    }
}

extension MediaColumnAvailabilityTests {
    @Test func videoMenuAndSavedColumnsExcludePhotoFacts() throws {
        let header = ListHeader()
        header.mediaKind = .video
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let titles = try #require(header.menu(for: event)).items.map(\.title)
        for title in ["Camera", "Lens", "ISO", "Date Taken", "Megapixels", "Photos", "Reading Direction"] {
            #expect(!titles.contains(title))
        }
        for title in ["Duration", "Codec", "Frame Rate", "Width", "Height"] { #expect(titles.contains(title)) }
        let browser = HomeBrowserView(source: FakeHomeSource())
        browser.tableColumns = [.name, .camera, .iso, .duration, .width]
        browser.files = .videos
        #expect(browser.availableTableColumns == [.name, .duration, .width])
        browser.files = .photos
        #expect(browser.availableTableColumns == [.name, .camera, .iso, .width])
    }

    @Test func renamedVideoStyleKeepsVideoCapabilities() {
        var style = FileStyle.videos
        style.noun = "clip"
        let browser = HomeBrowserView(source: FakeHomeSource())
        browser.files = style
        browser.tableColumns = [.name, .codec, .lens]
        #expect(browser.availableTableColumns == [.name, .codec])
    }
}
