import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

/// Board «Эскизы файлов» (2026-10-27): badges on the picture, the band with the name on a small `auto` tile.
@MainActor @Suite struct PhotoCardFactsTests {
    private func card(_ facts: FileFacts, format: String, width: CGFloat, names: GridNames, video: Bool = false) -> PhotoCard {
        let item = HomeCardItem(id: "a", title: "a.file", tooltip: "a", symbol: "photo", format: format,
                                bytes: 1_150_000_000, facts: facts)
        let c = PhotoCard(item: item)
        c.names = names
        c.showsFacts = video
        c.showsFactsLine = true
        c.aspect = video ? 16.0 / 9 : 1
        c.frame = CGRect(x: 0, y: 0, width: width, height: width + 40)
        c.layoutSubtreeIfNeeded()
        return c
    }

    private func badges(_ c: PhotoCard) -> [String] {
        c.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden && $0.layer?.cornerRadius == 4 }.map(\.stringValue)
    }

    @Test func photoBadgesAndVideoBadges() {
        let photo = card(FileFacts(width: 6000, height: 4000, iso: 400), format: "ARW", width: 220, names: .below)
        #expect(badges(photo) == ["24 MP", "RAW"])
        let video = card(FileFacts(width: 1280, height: 720, duration: 60, codec: "H.264", fps: 59.94, hdr: true),
                         format: "MP4", width: 300, names: .below, video: true)
        #expect(badges(video) == ["720p", "HDR", "60"])
        #expect(video.factsLabel.stringValue == "H.264 · 1.15 GB")   // the rest is on the picture
        let small = card(FileFacts(width: 6000, height: 4000), format: "JPG", width: 100, names: .below)
        #expect(badges(small).isEmpty)
    }

    @Test func autoNamesShowABandOnHover() {
        let c = card(FileFacts(width: 6000, height: 4000, exposure: 1.0 / 250), format: "JPG", width: 140, names: .auto)
        #expect(c.nameLabel.isHidden)
        c.isHovered = true
        c.layoutSubtreeIfNeeded()
        #expect(!c.nameLabel.isHidden && !c.factsLabel.isHidden)
        #expect(c.nameLabel.frame.maxY <= c.pictureRect.maxY)   // over the picture, not under it
    }
}
