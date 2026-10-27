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
        c.subviews.compactMap { $0 as? MediaBadge }.filter { !$0.isHidden }.map(\.label)
    }

    @Test func photoBadgesAndVideoBadges() {
        let photo = card(FileFacts(width: 6000, height: 4000, iso: 400), format: "ARW", width: 220, names: .below)
        #expect(badges(photo) == ["RAW", "24\u{00A0}MP"])
        let video = card(FileFacts(width: 3840, height: 2160, duration: 60, codec: "H.264", fps: 25, transfer: .hlg),
                         format: "MP4", width: 300, names: .below, video: true)
        #expect(badges(video) == ["UHD", "HLG"])
        #expect(video.factsLabel.stringValue == "H.264 · 1.1\u{00A0}GB")   // the rest is on the picture
        let small = card(FileFacts(width: 6000, height: 4000), format: "JPG", width: 100, names: .below)
        #expect(badges(small).isEmpty)
    }

    @Test func badgesAreNeutralAsTheGuideAsks() throws {
        let video = card(FileFacts(width: 3840, height: 2160, duration: 60, codec: "HEVC", fps: 25, transfer: .hlg),
                         format: "MOV", width: 300, names: .below, video: true)
        let badges = video.subviews.compactMap { $0 as? MediaBadge }
        let hlg = try #require(badges.first { $0.label == "HLG" }), uhd = try #require(badges.first { $0.label == "UHD" })
        #expect(hlg.layer?.backgroundColor == uhd.layer?.backgroundColor)
        #expect(hlg.layer?.borderWidth == 0)
    }

    @Test func aPhotoHasNoPathTooltip() {
        #expect(card(FileFacts(width: 6000, height: 4000), format: "JPG", width: 220, names: .below).toolTip == nil)
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
