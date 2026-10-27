import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

/// Files in the Cards style (file-cards spec §2): the picture at the left at the files' aspect, four rows at its right.
@MainActor @Suite struct FileCardTests {
    private func card(_ facts: FileFacts?, aspect: CGFloat = 16.0 / 9, progress: Double? = nil, subtitle: String? = nil) -> FileCard {
        let item = HomeCardItem(id: "a", title: "clip.mp4", subtitle: subtitle, tooltip: "a", symbol: "film",
                                progress: progress, format: "MP4", date: Date(timeIntervalSince1970: 1_717_200_000),
                                bytes: 1_200_000_000, facts: facts)
        let c = FileCard(item: item)
        c.aspect = aspect
        c.frame = CGRect(x: 0, y: 0, width: 300, height: 92)
        c.layoutSubtreeIfNeeded()
        return c
    }

    @Test func videoRows() {
        let c = card(FileFacts(width: 1920, height: 1080, duration: 750, codec: "HEVC", fps: 60))
        #expect(c.pictureFrame == CGRect(x: 8, y: 8, width: 135, height: 76))
        #expect(c.rowTexts[0] == "FHD · 60p · HEVC")
        #expect(c.rowTexts[1] == "12:30 · 1.2\u{00A0}GB")
        #expect(abs(c.nameFrame.minX - 154) < 0.01)   // 11 pt right of the picture
    }

    @Test func videoProgressLine() {
        let c = card(FileFacts(duration: 750, codec: "HEVC"), progress: 0.4, subtitle: "5:00 / 12:30")
        #expect(c.rowTexts[2] == "5:00 / 12:30")
    }

    @Test func photoRows() {
        let f = FileFacts(width: 4032, height: 3024, camera: "Sony ILCE-7M4", lens: "FE 24-70mm F2.8 GM II",
                          exposure: 1.0 / 250, aperture: 2.8, iso: 400)
        let c = card(f, aspect: 1)
        #expect(c.pictureFrame.size == CGSize(width: 76, height: 76))
        #expect(c.rowTexts[0] == "Sony ILCE-7M4 · FE 24-70mm F2.8 GM II")
        #expect(c.rowTexts[1] == "1/250 · f/2.8 · ISO\u{00A0}400")
        #expect(c.rowTexts[2].hasSuffix("4032 × 3024 · 1.2\u{00A0}GB"))
    }

    @Test func noFactsDrawsTheFormatDateAndSize() {
        let c = card(nil, aspect: 1)
        #expect(c.rowTexts[0] == "MP4")
        #expect(c.rowTexts[2].hasSuffix("1.2\u{00A0}GB"))
    }
}
