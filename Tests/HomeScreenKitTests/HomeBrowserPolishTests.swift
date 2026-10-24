import AppKit
import HomeChrome
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

    /// The loading line's glint runs at most `moveLimit`, then the line keeps still (the Reduce Motion look: the whole
    /// line at half strength) until the next load; nothing moves while it may not (the window hidden).
    @Test func loadingGlintEndsAfterItsTime() async {
        guard !Chrome.Motion.reduced else { return }   // the system's Reduce Motion: it never moves
        #expect(LoadingLine.defaultMoveLimit == .seconds(8))
        let line = LoadingLine()
        line.frame = CGRect(x: 0, y: 0, width: 400, height: 2)
        line.moveLimit = .milliseconds(150)
        line.run(true)
        #expect(line.isMoving)
        line.mayMove = false
        #expect(line.isRunning && !line.isMoving)
        line.mayMove = true
        #expect(line.isMoving)
        await settle(seconds: 5) { !line.isMoving }
        #expect(line.isRunning && !line.isMoving)
        #expect(line.glintFrame == line.bounds)   // still: the whole line
        // A new load moves again.
        line.run(false)
        line.run(true)
        #expect(line.isMoving)
    }

    /// The skeleton's shine likewise: at most `moveLimit`, then still until the next start.
    @Test func skeletonShineEndsAfterItsTime() async {
        guard !Chrome.Motion.reduced else { return }
        #expect(BrowserSkeleton.defaultMoveLimit == .seconds(8))
        let skeleton = BrowserSkeleton()
        skeleton.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        skeleton.moveLimit = .milliseconds(150)
        skeleton.start()
        #expect(skeleton.isMoving)
        skeleton.mayMove = false
        #expect(!skeleton.isMoving)
        skeleton.mayMove = true
        #expect(skeleton.isMoving)
        await settle(seconds: 5) { !skeleton.isMoving }
        #expect(!skeleton.isMoving)
        skeleton.stop()
        skeleton.start()
        #expect(skeleton.isMoving)
    }

    /// The window off screen (minimized, hidden, covered) or the browser hidden in it: the line and the skeleton keep
    /// still; back on screen, they move again.
    @Test func loadingMovesOnlyWhileOnScreen() async {
        guard !Chrome.Motion.reduced else { return }
        let view = make(FakeHomeSource())
        view.windowVisibleForTests = true
        view.windowVisibilityChanged()
        #expect(view.isShowingLoadingLine && view.loading.isMoving && view.isSkeletonMoving)
        view.windowVisibleForTests = false
        view.windowVisibilityChanged()
        #expect(view.isShowingLoadingLine && !view.loading.isMoving && !view.isSkeletonMoving)
        view.windowVisibleForTests = true
        view.windowVisibilityChanged()
        #expect(view.loading.isMoving && view.isSkeletonMoving)
        view.isHidden = true
        #expect(!view.loading.isMoving && !view.isSkeletonMoving)
        view.isHidden = false
        #expect(view.loading.isMoving && view.isSkeletonMoving)
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
