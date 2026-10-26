import CoreGraphics
import Testing
@testable import HomeScreenModel

@Suite struct HomeLayoutTests {
    let photo: CGFloat = 2.0 / 3
    let video: CGFloat = 9.0 / 16

    @Test func scrollKeepsCardSize() {
        let fit = HomeLayout.fit(mode: .scroll, area: CGSize(width: 1200, height: 800), cardSize: 220, aspect: photo,
                                 sections: [(24, true)])
        #expect(fit == HomeGridFit(columns: 4, cardWidth: 220, scrolls: true))   // (1136 + 20) / 240
    }

    @Test func fitShrinksToShowAll() {
        let sections = [(count: 10, heading: true)]
        let fit = HomeLayout.fit(mode: .fit, area: CGSize(width: 1200, height: 800), cardSize: 480, aspect: video,
                                 sections: sections)
        #expect(!fit.scrolls)
        #expect(fit.cardWidth >= 140 && fit.cardWidth <= 480)
        #expect(HomeLayout.contentHeight(fit, aspect: video, sections: sections) <= 800)
        #expect(fit.cardWidth == 269)
    }

    @Test func fitUsesCardSizeWhenRoomy() {
        let fit = HomeLayout.fit(mode: .fit, area: CGSize(width: 1600, height: 1200), cardSize: 220, aspect: photo,
                                 sections: [(3, true)])
        #expect(fit == HomeGridFit(columns: 3, cardWidth: 220, scrolls: false))
    }

    @Test func fitFallsBackToScroll() {
        let fit = HomeLayout.fit(mode: .fit, area: CGSize(width: 900, height: 500), cardSize: 220, aspect: photo,
                                 sections: [(4, true), (24, true)])
        #expect(fit == HomeGridFit(columns: 5, cardWidth: 140, scrolls: true))
    }

    @Test func fixedNeverScrolls() {
        let fit = HomeLayout.fit(mode: .fixed, area: CGSize(width: 900, height: 500), cardSize: 220, aspect: photo,
                                 sections: [(4, true), (24, true)])
        #expect(fit == HomeGridFit(columns: 5, cardWidth: 140, scrolls: false))
    }

    @Test func narrowerThanOneCard() {
        for mode in HomeLayoutMode.allCases {
            let fit = HomeLayout.fit(mode: mode, area: CGSize(width: 100, height: 300), cardSize: 220, aspect: photo,
                                     sections: [(5, true)])
            #expect(fit.columns == 1)
            #expect(fit.cardWidth > 0 && fit.cardWidth <= 36)
        }
    }

    @Test func zeroCards() {
        for mode in HomeLayoutMode.allCases {
            let fit = HomeLayout.fit(mode: mode, area: CGSize(width: 1000, height: 700), cardSize: 220, aspect: photo,
                                     sections: [])
            #expect(fit.columns >= 1)
            let m = HomeMetrics()
            #expect(HomeLayout.contentHeight(fit, aspect: photo, sections: []) == m.top + m.inset)
        }
    }

    @Test func headingsCount() {
        let fit = HomeGridFit(columns: 3, cardWidth: 200, scrolls: false)
        let m = HomeMetrics()
        let with = HomeLayout.contentHeight(fit, aspect: photo, sections: [(3, true)])
        let without = HomeLayout.contentHeight(fit, aspect: photo, sections: [(3, false)])
        #expect(with - without == m.headingHeight + m.headingGap)
    }

    @Test func cardHeightIsPictureAndText() {
        #expect(HomeLayout.cardHeight(width: 300, aspect: photo) == CGFloat(248))
    }
}

@Suite struct HomeResizeTests {
    @Test func stepsFromTheWidthOnScreenOnA20PointGrid() {
        #expect(HomeResize.larger.size(from: 180, range: 140...480) == 200)
        #expect(HomeResize.smaller.size(from: 180, range: 140...480) == 160)
        #expect(HomeResize.larger.size(from: 187, range: 140...480) == 200)   // a shrunk fit width snaps to the grid
        #expect(HomeResize.smaller.size(from: 187, range: 140...480) == 180)
    }

    @Test func staysInTheRange() {
        #expect(HomeResize.larger.size(from: 480, range: 140...480) == 480)
        #expect(HomeResize.smaller.size(from: 140, range: 140...480) == 140)
        #expect(HomeResize.smaller.size(from: 90, range: 140...480) == 140)
    }

    /// ⌘= / ⌘− go to the next of the four sizes, from anywhere between them, and stay past the ends.
    @Test func sizeStepsGoToTheNextSize() {
        #expect(HomeResize.nextSize(after: 100, larger: true) == 160)
        #expect(HomeResize.nextSize(after: 155, larger: true) == 240)   // 160 is within 5 %: not a step
        #expect(HomeResize.nextSize(after: 200, larger: false) == 160)
        #expect(HomeResize.nextSize(after: 360, larger: true) == 360)
        #expect(HomeResize.nextSize(after: 420, larger: true) == 420)
        #expect(HomeResize.nextSize(after: 420, larger: false) == 360)
        #expect(HomeResize.nextSize(after: 60, larger: false) == 60)
        #expect(HomeResize.largerSize.size(from: 240, range: 60...480) == 360)
        #expect(HomeResize.to(77).size(from: 240, range: 60...480) == 77)
    }

    @Test func resetIsNoSize() {
        #expect(HomeResize.reset.size(from: 300, range: 140...480) == nil)
    }
}
