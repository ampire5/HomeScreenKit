import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

/// Compact cards as mockup B: 300 × 92, a 76 pt cover inside 8 pt of padding, four rows at its right.
@MainActor @Suite struct CompactCardTests {
    private let summary = CardSummary(photos: 248, folders: 3, insidePhotos: 412, bytes: 1_900_000_000,
                                      first: Date(timeIntervalSince1970: 1_717_200_000),
                                      last: Date(timeIntervalSince1970: 1_723_000_000),
                                      histogram: [1, 3, 8, 10, 7, 4, 2, 1], viewed: 0.62, seen: 153, new: 12)

    private func card(_ summary: CardSummary?, badge: String? = nil, subtitle: String? = nil) -> CompactCard {
        let item = HomeCardItem(id: "a", title: "Vacation 2024", subtitle: subtitle, tooltip: "a", symbol: "folder",
                                badge: badge, summary: summary)
        let c = CompactCard(item: item)
        c.frame = CGRect(x: 0, y: 0, width: 300, height: 92)
        c.layoutSubtreeIfNeeded()
        return c
    }

    @Test func coverAndRows() {
        let c = card(summary)
        #expect(c.pictureFrame == CGRect(x: 8, y: 8, width: 76, height: 76))
        #expect(c.coverClip.layer?.cornerRadius == 8 && c.plate.cornerRadius == 12 && c.plate.frame == c.bounds)
        // the text column 11 pt right of the cover, 8 pt from the card's right edge
        let column = 8 + 76 + 11
        #expect(c.nameLabel.frame.minX == CGFloat(column))
        #expect(c.nameLabel.font.pointSize == 13.5)
        // four rows from 9 to 83, spread evenly
        #expect(c.rowTops.first == 9 && c.rowTops.last! + CompactCard.rows.last! == 83)
        // row 2: [photo] 248  [folder] 3 · 412  1.9 GB
        #expect(!c.photoIcon.isHidden && !c.folderIcon.isHidden)
        #expect(c.ownLabel.stringValue == "248" && c.foldersLabel.stringValue == "3\u{2005}· 412" && c.sizeLabel.stringValue == "1.9 GB")
        #expect(c.ownLabel.frame.minX == c.photoIcon.frame.maxX + 3)
        #expect(c.folderIcon.frame.minX == c.ownLabel.frame.maxX + 10)
        #expect(c.sizeLabel.frame.minX == c.foldersLabel.frame.maxX + 10)
        // row 3: bars 3 pt wide and the span
        #expect(c.histogram.barWidth == 3 && !c.histogram.isHidden && c.yearsLabel.stringValue == "Jun – Aug 2024")
        #expect(c.yearsLabel.frame.minX == c.histogram.frame.maxX + 8)
        // row 4: the track, "153 / 248", "+12" at the end
        #expect(c.viewedLabel.stringValue == "153 / 248" && c.newPill.text == "+12")
        #expect(c.newPill.frame.maxX == 292 && c.viewedLabel.frame.maxX + 7 == c.newPill.frame.minX)
        #expect(c.progressTrack.frame.minX == CGFloat(column) && c.progressTrack.frame.maxX + 7 == c.viewedLabel.frame.minX)
        #expect(c.progressTrack.frame.height == 4)
        let tops = [c.nameLabel, c.ownLabel, c.yearsLabel, c.viewedLabel].map(\.frame.minY)
        #expect(tops == tops.sorted())
        for view in [c.nameLabel, c.ownLabel, c.sizeLabel, c.histogram, c.yearsLabel, c.progressTrack, c.viewedLabel, c.newPill] as [NSView] {
            #expect(view.frame.minY >= 8 && view.frame.maxY <= 84, "\(view)")
        }
    }

    @Test func archiveAndBadges() {
        var s = CardSummary(photos: 96, bytes: 1_200_000_000, histogram: [0, 0, 10, 0], viewed: 1, done: true,
                            twoPages: true, rightToLeft: true)
        s.first = Date(timeIntervalSince1970: 1_678_000_000)
        s.last = s.first
        let c = card(s, badge: "ZIP")
        #expect(!c.coverChip.isHidden && c.coverChip.frame.minX == 12 && c.coverChip.frame.maxY == 80)
        #expect(!c.twoPagesIcon.isHidden && !c.rtlLabel.isHidden && c.folderIcon.isHidden)
        #expect(c.twoPagesIcon.frame.size == CGSize(width: 14, height: 14))
        #expect(c.viewedLabel.stringValue == "viewed" && c.checkIcon.isHidden)
        #expect(c.yearsLabel.stringValue == "Mar 2023")
    }

    @Test func unavailableShowsTheWarningRow() {
        var s = summary
        s.problem = .offline
        let c = card(s)
        #expect(c.picture.alphaValue == 0.4 && c.alphaValue == 1)
        #expect(!c.warningLabel.isHidden && c.warningLabel.stringValue == "Network volume not connected · facts from the catalog")
        #expect(!c.problemIcon.isHidden && c.problemIcon.frame.size == CGSize(width: 12, height: 12))
        #expect(c.progressTrack.isHidden && c.viewedLabel.isHidden && c.newPill.isHidden)
        #expect(c.warningLabel.frame.minX == c.problemIcon.frame.maxX + 5)
    }

    @Test func withoutSummaryTheSubtitle() {
        let c = card(nil, subtitle: "12 photos")
        #expect(!c.fallbackLabel.isHidden && c.fallbackLabel.stringValue == "12 photos")
        #expect(c.photoIcon.isHidden && c.histogram.isHidden && c.progressTrack.isHidden)
    }

    @Test func renameFieldSitsOnTheName() {
        let c = card(summary)
        #expect(c.nameFrame.minY == c.nameLabel.frame.minY && c.nameFrame.height == c.nameLabel.frame.height)
        #expect(c.nameFrame.minX == c.nameLabel.frame.minX && c.nameFrame.width >= c.nameLabel.frame.width)
    }

    /// Row 4 says when the folder was viewed, after the progress; in the same 11 pt, the same gaps.
    @Test func compactRowFourHasRecency() {
        FolderCard.now = { CardTestClock.now }
        var s = summary
        s.visited = CardTestClock.threeDaysAgo
        let c = card(s)
        #expect(c.viewedLabel.stringValue == "153 / 248 · 3 d ago" && c.viewedLabel.font.pointSize == 11)
        #expect(c.newPill.frame.maxX == 292 && c.viewedLabel.frame.maxX + 7 == c.newPill.frame.minX)
        #expect(c.progressTrack.frame.maxX + 7 == c.viewedLabel.frame.minX)
        var done = CardSummary(photos: 96, viewed: 1, seen: 96, done: true)
        done.visited = CardTestClock.threeDaysAgo
        #expect(card(done).viewedLabel.stringValue == "viewed · 3 d ago")
        #expect(card(CardSummary(photos: 12)).viewedLabel.stringValue == "not opened")
    }

    /// The board's waiting card (B): the 76 pt placeholder (radius 8, #E4E4E0), the name at once, two lines 10 pt high
    /// (radius 4, #ECECE8, 70 % and 45 % of the column) spread under it to the bottom; no progress, no facts text.
    @Test func waitingCardAsTheBoardDrawsIt() {
        FolderCard.reduceMotion = { false }
        let item = HomeCardItem(id: "a", title: "Mountains", subtitle: "12 photos", tooltip: "a", symbol: "folder",
                                waiting: true)
        let c = CompactCard(item: item)
        c.appearance = NSAppearance(named: .aqua)
        c.frame = CGRect(x: 0, y: 0, width: 300, height: 92)
        c.layoutSubtreeIfNeeded()
        let k = c.skeleton!
        #expect(k.coverClip.frame == CGRect(x: 8, y: 8, width: 76, height: 76) && k.cover.frame.height == 76 && k.cover.cornerRadius == 8)
        #expect(k.cover.backgroundColor == NSColor(srgbRed: 0xE4 / 255.0, green: 0xE4 / 255.0, blue: 0xE0 / 255.0,
                                                            alpha: 1).cgColor)
        let column: CGFloat = 300 - 95 - 8
        let lines = k.lines.filter { !$0.isHidden }
        #expect(lines.map(\.frame) == [CGRect(x: 95, y: 44, width: (column * 0.7).rounded(), height: 10),
                                       CGRect(x: 95, y: 73, width: (column * 0.45).rounded(), height: 10)])
        #expect(lines.allSatisfy { $0.cornerRadius == 4 })
        #expect(lines.first?.backgroundColor == NSColor(srgbRed: 0xEC / 255.0, green: 0xEC / 255.0, blue: 0xE8 / 255.0,
                                                        alpha: 1).cgColor)
        #expect(!c.nameLabel.isHidden && c.fallbackLabel.isHidden && c.progressTrack.isHidden)
        #expect(c.shimmer?.animation(forKey: FolderCard.shimmerKey) != nil)
    }
}

/// A fixed "now" for the cards' recency words (noon UTC mid-month: three days back is three calendar days in any
/// time zone).
enum CardTestClock {
    static let now = Date(timeIntervalSince1970: 1_791_979_200)   // 2026-10-14 12:00 UTC
    static let threeDaysAgo = now.addingTimeInterval(-3 * 86_400)

}
