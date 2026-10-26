import Foundation
import Testing
@testable import HomeScreenModel

@MainActor @Suite struct UnreadableFilesTests {
    private let a = URL(fileURLWithPath: "/f/a.jpg")
    private let day = Date(timeIntervalSinceReferenceDate: 100)

    @Test func markedIsContained() {
        let files = UnreadableFiles()
        #expect(!files.contains(a, date: day, size: 5))
        files.mark(a, date: day, size: 5)
        #expect(files.contains(a, date: day, size: 5))
        #expect(files.contains(BrowserEntry(url: a, name: "a.jpg", kind: .file, date: day, size: 5)))
    }

    @Test func clearForgets() {
        let files = UnreadableFiles()
        files.mark(a, date: day, size: 5)
        files.clear(a)
        #expect(!files.contains(a, date: day, size: 5))
    }

    @Test func otherVersionIsUnknown() {   // replaced or mended since: tried again
        let files = UnreadableFiles()
        files.mark(a, date: day, size: 5)
        #expect(!files.contains(a, date: day, size: 6))
        #expect(!files.contains(a, date: day.addingTimeInterval(1), size: 5))
    }

    @Test func withoutDateMatchesByURL() {   // a names-only listing, or a failure without the file's facts
        let files = UnreadableFiles()
        files.mark(a, date: nil, size: nil)
        #expect(files.contains(a, date: day, size: 5))
        let other = UnreadableFiles()
        other.mark(a, date: day, size: 5)
        #expect(other.contains(a, date: nil, size: nil))
    }

    @Test func urlsAreStandardized() {
        let files = UnreadableFiles()
        files.mark(URL(fileURLWithPath: "/f/./a.jpg"), date: nil, size: nil)
        #expect(files.contains(a, date: nil, size: nil))
    }

    @Test func observerGetsOnlyChanges() {
        let files = UnreadableFiles()
        var seen: [Set<URL>] = []
        let observation = files.observe { seen.append($0) }
        files.mark(a, date: day, size: 5)
        files.mark(a, date: day, size: 5)    // the same again: nobody woken
        files.clear(URL(fileURLWithPath: "/f/b.jpg"))   // not marked: nothing
        files.clear(a)
        #expect(seen == [[a], [a]])
        _ = observation
    }

    @Test func droppedObservationIsSilent() {
        let files = UnreadableFiles()
        var calls = 0
        var observation: UnreadableFiles.Observation? = files.observe { _ in calls += 1 }
        _ = observation
        observation = nil
        files.mark(a, date: nil, size: nil)
        #expect(calls == 0)
    }
}
