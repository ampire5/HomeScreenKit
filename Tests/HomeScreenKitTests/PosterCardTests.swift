import AppKit
import Testing
@testable import HomeScreenKit
@testable import HomeScreenModel

@MainActor @Suite struct PosterCardTests {
    private let summary = CardSummary(photos: 248, folders: 3, bytes: 4_200_000_000,
                                      first: Date(timeIntervalSince1970: 1_560_000_000),
                                      last: Date(timeIntervalSince1970: 1_690_000_000),
                                      histogram: [10, 40, 90, 20, 0, 0, 5, 5, 30, 25, 20, 10], viewed: 0.55)

    private func card(_ summary: CardSummary?, width: CGFloat, count: Int? = nil, subtitle: String? = nil) -> PosterCard {
        let item = HomeCardItem(id: "a", title: "Holiday", subtitle: subtitle, tooltip: "a", symbol: "folder",
                                progress: nil, summary: summary, count: count)
        let card = PosterCard(item: item)
        card.frame = CGRect(x: 0, y: 0, width: width, height: width + GridLayout.bandHeight(width: width))
        card.layoutSubtreeIfNeeded()
        return card
    }

    @Test func posterDrawsBandBelowPicture() {
        var s = summary
        s.twoPages = true
        s.rightToLeft = true
        s.new = 12
        let c = card(s, width: 270)
        #expect(c.pictureFrame == CGRect(x: 0, y: 0, width: 270, height: 270))
        #expect(c.bounds.height == 270 + GridLayout.bandHeight(width: 270))
        for view in [c.nameLabel, c.insideLabel, c.sizeLabel, c.yearsLabel, c.histogram] as [NSView] {
            #expect(!view.isHidden)
            #expect(view.frame.minY >= 270)           // nothing of the band over the picture
            #expect(view.frame.maxY <= c.bounds.height)
        }
        // the badges are on the name line
        #expect(!c.twoPagesIcon.isHidden && !c.rtlLabel.isHidden)
        for badge in [c.twoPagesIcon, c.rtlLabel] as [NSView] {
            #expect(badge.frame.intersects(c.nameLabel.frame) == false)
            #expect(badge.frame.midY == c.nameLabel.frame.midY || abs(badge.frame.midY - c.nameLabel.frame.midY) < 6)
            #expect(badge.frame.minY >= 270)
        }
        #expect(c.insideLabel.stringValue == "248 · 3 folders")
        #expect(c.sizeLabel.stringValue == "4.2 GB")
        // "+12" on the cover's corner, not in the band
        #expect(!c.flagPill.isHidden && c.flagPill.text == "+12")
        #expect(c.pictureFrame.contains(c.flagPill.frame))
        // the thin line on the seam
        #expect(!c.progressBar.isHidden)
        #expect(abs(c.progressFrame.maxY - 270) <= 3.01)
        #expect(abs(c.progressFrame.width - (270 * 0.55).rounded()) < 1)
    }

    @Test func whatDoesNotFitIsDropped() {
        // 200 pt: the count and the size first, the years with their bars only if there is room
        let c = card(summary, width: 200)
        #expect(!c.insideLabel.isHidden && !c.sizeLabel.isHidden)
        let shown = [c.insideLabel, c.histogram, c.yearsLabel, c.sizeLabel].filter { !$0.isHidden }.map(\.frame)
            .sorted { $0.minX < $1.minX }
        for (a, b) in zip(shown, shown.dropFirst()) { #expect(a.maxX <= b.minX) }
        #expect(shown.last!.maxX <= 200)
        #expect(c.histogram.isHidden == c.yearsLabel.isHidden)
    }

    @Test func doneShowsCheck() {
        var s = summary
        s.done = true
        s.viewed = 1
        let c = card(s, width: 270)
        #expect(!c.flagPill.isHidden && c.flagPill.text == "✓")
        #expect(card(summary, width: 270).flagPill.isHidden)
    }

    @Test func posterNarrowHasOneLine() {
        let c = card(summary, width: 180)
        #expect(c.bounds.height == 180 + GridLayout.bandHeight(width: 180))
        #expect(!c.nameLabel.isHidden && !c.countLabel.isHidden)
        #expect(c.countLabel.stringValue == "248")
        for view in [c.insideLabel, c.sizeLabel, c.yearsLabel, c.histogram, c.viewedLabel, c.fallbackLabel] as [NSView] {
            #expect(view.isHidden)
        }
        #expect(c.nameLabel.frame.maxY <= c.bounds.height)
    }

    @Test func widthDecidesWhatTheSecondLineHolds() {
        let two = card(summary, width: 270)
        #expect(two.viewedLabel.isHidden)
        let wide = card(summary, width: 320)
        #expect(!wide.viewedLabel.isHidden)
        #expect(wide.viewedLabel.stringValue == "136 / 248")
        #expect(wide.viewedLabel.frame.minY >= 320)
        // every item of the line stays inside the card and clear of its neighbours
        let line = [wide.insideLabel, wide.histogram, wide.yearsLabel, wide.viewedLabel, wide.sizeLabel]
            .filter { !$0.isHidden }.map(\.frame).sorted { $0.minX < $1.minX }
        for (a, b) in zip(line, line.dropFirst()) { #expect(a.maxX <= b.minX) }
        #expect(line.last!.maxX <= 320)
    }

    @Test func withoutSummaryItShowsWhatItShowedBefore() {
        let c = card(nil, width: 270, count: 12, subtitle: "12 photos")
        #expect(c.fallbackLabel.stringValue == "12 photos" && !c.fallbackLabel.isHidden)
        #expect(c.insideLabel.isHidden && c.histogram.isHidden && c.flagPill.isHidden && c.progressBar.isHidden)
        let narrow = card(nil, width: 180, count: 12, subtitle: "12 photos")
        #expect(narrow.countLabel.stringValue == "12")
    }

    @Test func histogramScalesToLargestBin() {
        let h = HistogramView.heights([10, 40, 90, 0, 45], height: 12)
        let expected: [CGFloat] = [12.0 * 10 / 90, 12.0 * 40 / 90, 12, 0, 6]
        #expect(h == expected)
        #expect(HistogramView.heights([0, 0], height: 12) == [0, 0])
        #expect(HistogramView.heights([], height: 12).isEmpty)
        // a bin with photos is never invisible
        #expect(HistogramView.heights([1, 255], height: 12)[0] >= 1)
    }

    @Test func problemsShowBadge() {
        var s = summary
        s.problem = .broken
        #expect(!card(s, width: 270).problemIcon.isHidden)
        s.problem = .offline
        #expect(!card(s, width: 270).problemIcon.isHidden)
        #expect(card(summary, width: 270).problemIcon.isHidden)
    }

    @Test func compactCardHasFourLines() {
        var s = summary
        s.new = 3
        s.twoPages = true
        let item = HomeCardItem(id: "a", title: "Holiday", tooltip: "a", symbol: "folder", summary: s, count: 248)
        let c = CompactCard(item: item)
        c.frame = CGRect(x: 0, y: 0, width: 300, height: 92)
        c.layoutSubtreeIfNeeded()
        #expect(c.pictureFrame == CGRect(x: 0, y: 0, width: 92, height: 92))
        let lines = [c.nameLabel, c.insideLabel, c.yearsLabel, c.viewedLabel] as [NSView]
        for view in lines {
            #expect(!view.isHidden)
            #expect(view.frame.minX >= 92)
            #expect(c.bounds.contains(view.frame))
        }
        let ys = lines.map { $0.frame.minY }
        #expect(ys == ys.sorted())
        #expect(c.insideLabel.stringValue == "248 · 3 folders · 4.2 GB")
        #expect(c.flagPill.text == "+3" && c.bounds.contains(c.flagPill.frame))
        #expect(c.flagPill.frame.minX >= 92)
        #expect(c.bounds.contains(c.progressFrame) && c.progressFrame.minX >= 92)
    }
}
