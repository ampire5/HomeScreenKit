import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

/// Posters as mockup E: one card holding the cover, the seam and the band, the band's lines by width.
@MainActor @Suite struct PosterCardTests {
    private let summary = CardSummary(photos: 248, folders: 3, insidePhotos: 412, bytes: 1_900_000_000,
                                      first: Date(timeIntervalSince1970: 1_717_200_000),   // June 2024
                                      last: Date(timeIntervalSince1970: 1_723_000_000),    // August 2024
                                      histogram: [1, 3, 8, 10, 7, 4, 2, 1, 0, 0, 0, 0], viewed: 0.62, seen: 153)

    private func card(_ summary: CardSummary?, width: CGFloat, badge: String? = nil, count: Int? = nil,
                      subtitle: String? = nil) -> PosterCard {
        let item = HomeCardItem(id: "a", title: "Vacation 2024", subtitle: subtitle, tooltip: "a", symbol: "folder",
                                progress: nil, badge: badge, summary: summary, count: count)
        let card = PosterCard(item: item)
        card.frame = CGRect(x: 0, y: 0, width: width, height: width + GridLayout.bandHeight(width: width))
        card.layoutSubtreeIfNeeded()
        return card
    }

    /// The mockup's three sizes: a 32 / 51 / 68 pt seam and band under the cover.
    @Test func bandHeightsAtTheMockupsSizes() {
        let small: CGFloat = 3 + 6 + 15 + 8, normal: CGFloat = 3 + 7 + 16 + 3 + 13 + 9
        let large: CGFloat = 3 + 6 + 17 + 3 + 14 + 3 + 14 + 8
        #expect(GridLayout.bandHeight(width: 176) == small)
        #expect(GridLayout.bandHeight(width: 232) == normal)
        #expect(GridLayout.bandHeight(width: 300) == large)
        #expect(GridLayout.bandHeight(width: 199.5) == GridLayout.bandHeight(width: 176))
        #expect(GridLayout.bandHeight(width: 200) == GridLayout.bandHeight(width: 232))
        #expect(GridLayout.bandHeight(width: 280) == GridLayout.bandHeight(width: 300))
    }

    @Test func oneCardWithCoverSeamAndBand() {
        var s = summary
        s.new = 12
        let c = card(s, width: 232)
        #expect(c.pictureFrame == CGRect(x: 0, y: 0, width: 232, height: 232))
        #expect(c.plate.frame == c.bounds && c.plate.cornerRadius == 12)
        // the seam: a 3 pt track under the cover, filled 62 %
        #expect(c.progressTrack.frame == CGRect(x: 0, y: 232, width: 232, height: 3))
        #expect(c.progressBar.frame == CGRect(x: 0, y: 232, width: (232 * 0.62).rounded(), height: 3))
        // the band: 10 pt from the sides, the name 7 pt under the seam
        #expect(c.nameLabel.frame.minX == 10 && c.nameLabel.frame.minY == 235 + 7)
        #expect(c.nameLabel.font.pointSize == 13)
        for view in [c.nameLabel, c.insideLabel, c.yearsLabel, c.newPill] as [NSView] {
            #expect(!view.isHidden)
            #expect(view.frame.minY >= 235 && view.frame.maxY <= c.bounds.height)
            #expect(view.frame.minX >= 10 && view.frame.maxX <= 222)
        }
        // "+12" at the name line's end, the years at the facts line's end
        #expect(c.newPill.frame.maxX == 222 && abs(c.newPill.frame.midY - c.nameLabel.frame.midY) <= 1)
        #expect(c.yearsLabel.frame.maxX == 222 && c.yearsLabel.stringValue == "2024")
        // The facts stay whole (owner, 2026-10-23): the bars go when they would cut the text.
        #expect(c.insideLabel.stringValue == "248 photos · 3 folders · 1.9 GB")
        #expect(c.insideLabel.textWidth <= c.insideLabel.frame.width)
        #expect(c.insideLabel.frame.maxX + 8 <= c.yearsLabel.frame.minX)
        #expect(c.histogram.isHidden)
    }

    /// Short facts leave room: the bars sit between the text and the years, as board E draws them.
    @Test func barsStayWhenTheyFit() {
        var s = CardSummary(photos: 96, bytes: 1_200_000_000, first: Date(timeIntervalSince1970: 1_678_000_000),
                            last: Date(timeIntervalSince1970: 1_679_000_000), histogram: [0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        s.twoPages = true
        let c = card(s, width: 232, badge: "ZIP")
        #expect(c.insideLabel.stringValue == "96 pages · 1.2 GB")
        #expect(!c.histogram.isHidden)
        #expect(c.insideLabel.frame.maxX + 8 == c.histogram.frame.minX)
        #expect(c.histogram.frame.maxX + 8 == c.yearsLabel.frame.minX && c.yearsLabel.frame.maxX == 222)
        #expect(c.histogram.barWidth == 2.5 && c.histogram.barGap == 1.5 && c.histogram.frame.height == 12)
    }

    /// Whatever the card cuts, the tooltip has it all: the facts with the subfolders' photos, the span and the
    /// progress, then the path the item gave.
    @Test func tooltipCarriesTheWholeFacts() {
        let c = card(summary, width: 232)
        #expect(c.toolTip == "248 photos · 3 folders (412) · 1.9 GB\nJun – Aug 2024 · 153 / 248\na")
        #expect(card(nil, width: 232).toolTip == "a")
    }

    @Test func narrowPosterHasTheNameAndThePill() {
        var s = summary
        s.new = 12
        let c = card(s, width: 176)
        #expect(c.nameLabel.font.pointSize == 12 && !c.newPill.isHidden)
        for view in [c.insideLabel, c.histogram, c.yearsLabel, c.viewedLabel, c.warningLabel, c.sizeLabel] as [NSView] {
            #expect(view.isHidden)
        }
        #expect(c.nameLabel.frame.maxY + 8 == c.bounds.height)
    }

    @Test func largePosterAddsTheSpanAndProgress() {
        let c = card(summary, width: 300)
        #expect(c.nameLabel.font.pointSize == 14)
        #expect(c.insideLabel.stringValue == "248 photos · 3 folders (412) · 1.9 GB")
        #expect(c.insideLabel.font.pointSize == 12)
        #expect(c.viewedLabel.stringValue == "Jun – Aug 2024 · 153 / 248" && !c.viewedLabel.isHidden)
        #expect(c.histogram.barWidth == 4 && c.histogram.frame.height == 14 && c.histogram.frame.minX == 10)
        #expect(c.viewedLabel.frame.minX == c.histogram.frame.maxX + 8)
        #expect(c.viewedLabel.frame.minY > c.insideLabel.frame.maxY && c.yearsLabel.isHidden)
        #expect(c.viewedLabel.frame.maxY + 8 == c.bounds.height)
    }

    @Test func badgesFollowTheNameAndDoneShowsCheck() {
        var s = summary
        s.twoPages = true
        s.rightToLeft = true
        s.done = true
        s.viewed = 1
        let c = card(s, width: 232, badge: "ZIP")
        #expect(!c.twoPagesIcon.isHidden && !c.rtlLabel.isHidden && !c.checkIcon.isHidden && c.newPill.isHidden)
        #expect(c.twoPagesIcon.frame.minX == c.nameLabel.frame.maxX + 6)
        #expect(c.rtlLabel.frame.minX == c.twoPagesIcon.frame.maxX + 6)
        #expect(c.checkIcon.frame.maxX == 222)
        // the archive's chip at the cover's top left; its count is pages when it is read as a book
        #expect(!c.coverChip.isHidden && c.coverChip.frame.origin == CGPoint(x: 8, y: 8))
        #expect(c.insideLabel.stringValue.hasPrefix("248 pages"))
    }

    /// Short of room the badges after the name go (RTL first); the pill at the end stays, the name is cut.
    @Test func badgesGiveWayOnANarrowPoster() {
        var s = summary
        s.twoPages = true
        s.rightToLeft = true
        s.new = 12
        let c = card(s, width: 120)
        #expect(c.rtlLabel.isHidden && !c.newPill.isHidden)
        #expect(c.nameLabel.frame.maxX + 6 <= c.newPill.frame.minX)
        #expect(c.newPill.frame.maxX == 110)
    }

    /// An unavailable folder: the cover faint with a glyph on it, a warning line in place of the facts, the band
    /// readable (the card is not dimmed as a whole). A damaged archive: the same with its own words.
    @Test func unavailableAndBroken() {
        var off = summary
        off.problem = .offline
        let c = card(off, width: 232)
        #expect(c.alphaValue == 1 && c.picture.alphaValue == 0.4)
        #expect(!c.coverAlert.isHidden && c.coverAlert.frame.size == CGSize(width: 34, height: 34))
        #expect(!c.warningLabel.isHidden && c.warningLabel.stringValue == "Not connected · facts from the catalog")
        #expect(c.insideLabel.isHidden && c.histogram.isHidden && c.yearsLabel.isHidden)
        #expect(c.warningLabel.textWidth <= c.warningLabel.frame.width)   // whole at the default size
        var broken = CardSummary(bytes: 310_000_000)
        broken.problem = .broken
        let b = card(broken, width: 232, badge: "CBZ")
        #expect(b.picture.alphaValue == 0.25 && !b.coverAlert.isHidden)
        #expect(b.warningLabel.stringValue == "Archive is damaged")
        #expect(b.warningLabel.textWidth <= b.warningLabel.frame.width)
        #expect(card(summary, width: 232).coverAlert.isHidden)
    }

    @Test func withoutSummaryItShowsWhatItShowedBefore() {
        let c = card(nil, width: 270, count: 12, subtitle: "12 photos")
        #expect(c.insideLabel.stringValue == "12 photos" && !c.insideLabel.isHidden)
        #expect(c.histogram.isHidden && c.newPill.isHidden && c.progressBar.isHidden && !c.progressTrack.isHidden)
    }

    @Test func renameFieldSitsOnTheName() {
        let c = card(summary, width: 232)
        #expect(c.nameFrame.minY == c.nameLabel.frame.minY && c.nameFrame.height == c.nameLabel.frame.height)
        #expect(c.nameFrame.minX == c.nameLabel.frame.minX && c.nameFrame.width >= c.nameLabel.frame.width)
    }

    @Test func histogramAsTheMockupDrawsIt() {
        // scaled to the largest bin, whole points, an empty bin a 1 pt stub
        #expect(HistogramView.heights([1, 3, 8, 10, 7, 4, 2, 1], height: 12) == [1, 4, 10, 12, 8, 5, 2, 1])
        #expect(HistogramView.heights([0, 10, 0], height: 12) == [1, 12, 1])
        #expect(HistogramView.heights([0, 0], height: 12) == [1, 1])   // no dated photo: the stubs alone
        #expect(HistogramView.heights([], height: 12).isEmpty)
        let h = HistogramView()
        h.bins = [1, 2, 3]
        #expect(h.barsWidth == CGFloat(10.5))
    }
}
