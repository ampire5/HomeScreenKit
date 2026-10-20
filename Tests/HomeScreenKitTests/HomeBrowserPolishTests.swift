import AppKit
import Testing
@testable import HomeScreenKit

/// The card frame, the picture shape and the loading indicator (second round of the file browser).
@MainActor @Suite struct HomeBrowserPolishTests {
    let x = URL(fileURLWithPath: "/Volumes/T/x")

    func make(_ source: FakeHomeSource) -> HomeBrowserView {
        let view = HomeBrowserView(source: source)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.slowAfter = .milliseconds(100)
        view.show(.folder(x), selecting: nil)
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test func selectionRingStandsApartFromThePicture() {
        let card = HomeCard(item: HomeCardItem(id: "a", title: "a", tooltip: "a", symbol: "photo"), aspect: 2.0 / 3)
        card.frame = CGRect(x: 0, y: 0, width: 200, height: 180)
        card.layoutSubtreeIfNeeded()
        #expect(card.ring.isHidden)
        card.isSelected = true
        #expect(!card.ring.isHidden)
        #expect(card.ring.frame.minX < 0 && card.ring.frame.width > 200)   // outside the picture, with a gap
        #expect(card.ring.borderWidth > 0)
    }

    @Test func styleReachesPhotoCards() async {
        let source = FakeHomeSource()
        let view = make(source)
        source.yield(x, BrowserFixtures.files(3))
        await settle { !view.entries.isEmpty }
        view.layoutSubtreeIfNeeded()
        #expect((view.card(for: view.entries[0].id) as? PhotoCard)?.style == .aspect)
        view.style = .square
        #expect((view.card(for: view.entries[0].id) as? PhotoCard)?.style == .square)
    }

    @Test func partialNamesShowAsTheyCome() async {
        let source = FakeHomeSource()
        let view = make(source)
        source.yieldPartial(x, BrowserFixtures.files(2))
        await settle { view.entries.count == 2 }
        #expect(view.toolbar.subtitleText == "Loading… 2")
        #expect(view.isShowingLoadingLine)
        source.yield(x, BrowserFixtures.files(5))
        await settle { view.entries.count == 5 }
        #expect(view.footerLines.first?.hasPrefix("5 ") == true)
        #expect(view.toolbar.subtitleText.hasPrefix(view.entries[0].name))   // the selected card
        #expect(!view.isShowingLoadingLine)
    }

    @Test func skeletonWhileNothingCame() async {
        let source = FakeHomeSource()
        let view = make(source)
        #expect(view.isShowingSkeleton)
        source.yieldPartial(x, BrowserFixtures.files(1))
        await settle { !view.entries.isEmpty }
        #expect(!view.isShowingSkeleton)
    }

    @Test func skeletonCardsAreCardSized() {
        let source = FakeHomeSource()
        let view = HomeBrowserView(source: source)   // sized only after it shows a place, as under constraints
        view.show(.folder(x), selecting: nil)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        view.layoutSubtreeIfNeeded()
        let frames = view.skeletonPictureFrames
        #expect(!frames.isEmpty)
        #expect(frames.allSatisfy { $0.width > 150 })   // the card width (220 here), not a sliver
    }

    @Test func slowFolderSaysSo() async throws {
        let source = FakeHomeSource()
        let view = make(source)
        for _ in 0..<40 where view.slowText == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(view.slowText?.contains("Waiting for the share") == true)
        source.yieldPartial(x, BrowserFixtures.files(3))
        for _ in 0..<40 where view.slowText?.contains("3 items so far") != true { try await Task.sleep(for: .milliseconds(50)) }
        #expect(view.slowText?.contains("3 items so far") == true)
        source.yield(x, BrowserFixtures.files(3))
        await settle { view.slowText == nil }
        #expect(view.slowText == nil)
    }
}
