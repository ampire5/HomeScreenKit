import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct RecursiveFolderFilesTests {
    @Test func readsNestedMediaWithoutFollowingLinksOrPackages() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        for name in ["nested", "nested/deeper", ".hidden", "sample.app"] {
            try manager.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        for name in ["top.MP4", "nested/deeper/inside.mp4", "nested/ignore.txt", ".hidden/secret.mp4", "sample.app/private.mp4"] {
            try Data([0]).write(to: root.appendingPathComponent(name))
        }
        try manager.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)

        let entries = try RecursiveFolderFiles.read(in: root, extensions: ["mp4"])
        #expect(Set(entries.map(\.name)) == ["top.MP4", "inside.mp4"])
        #expect(entries.allSatisfy { $0.isFile && $0.size == 1 })
        #expect(entries.first { $0.name == "inside.mp4" }?.url == root.appendingPathComponent("nested/deeper/inside.mp4"))
        #expect(throws: CancellationError.self) {
            try RecursiveFolderFiles.read(in: root, extensions: ["mp4"], cancelled: { true })
        }
    }

    @Test func snapshotsKeepDistinctPathsWithTheSameFileName() throws {
        let original = URL(fileURLWithPath: "/Volumes/Old/Collection")
        let new = URL(fileURLWithPath: "/Volumes/New/Collection")
        let entries = ["first", "second"].map {
            BrowserEntry(url: original.appendingPathComponent("\($0)/clip.mp4"), name: "clip.mp4", kind: .file,
                         date: Date(timeIntervalSinceReferenceDate: 10), size: 12)
        }
        let data = try #require(RecursiveListingSnapshot.encode(entries, in: original))
        let decoded = try #require(RecursiveListingSnapshot.decode(data, in: new))
        #expect(decoded.map(\.url.path) == ["/Volumes/New/Collection/first/clip.mp4", "/Volumes/New/Collection/second/clip.mp4"])
        #expect(decoded.map(\.date) == entries.map(\.date))
        #expect(decoded.allSatisfy { !$0.canRename && !$0.canTrash && $0.size == 12 })
    }

    @Test func duplicateFavoritesNameTheCorrectDisk() {
        let first = URL(fileURLWithPath: "/Volumes/Media/Clips")
        let second = URL(fileURLWithPath: "/Users/user/Network/NAS/Clips")
        let local = URL(fileURLWithPath: "/Users/user/Clips")
        let unique = URL(fileURLWithPath: "/Volumes/Media/Other")
        let hints = HomeFavorites.locationHints(for: [first, second, local, unique],
                                          volumes: [(URL(fileURLWithPath: "/Users/user/Network/NAS"), "Archive")],
                                          startupDisk: "Macintosh HD")
        #expect(hints[first] == "Media")
        #expect(hints[second] == "Archive")
        #expect(hints[local] == "Macintosh HD")
        #expect(hints[unique] == nil)
    }
}
