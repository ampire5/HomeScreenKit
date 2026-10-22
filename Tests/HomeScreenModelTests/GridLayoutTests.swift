import CoreGraphics
import Testing
@testable import HomeScreenModel

@Suite struct GridLayoutTests {
    private let m = GridMetrics()

    private func photos(_ n: Int, title: String? = nil) -> GridSection { GridSection(kind: .photos, count: n, title: title) }
    private func folders(_ n: Int, title: String? = nil) -> GridSection { GridSection(kind: .collections, count: n, title: title) }

    @Test func columnsFillAnyWidth() {
        for width: CGFloat in [100, 333, 1000, 1999, 4000] {
            for target: CGFloat in [60, 220, 480] {
                let grid = GridLayout(sections: [photos(10_000)], width: width, target: target, names: .off)
                let columns = grid.columns(inSection: 0)
                #expect(columns >= 1)
                let last = grid.frame(of: columns - 1)
                #expect(abs(last.maxX - (width - m.photoEdge)) <= 0.5, "width \(width) target \(target)")
            }
        }
        #expect(GridLayout(sections: [photos(5)], width: 100, target: 220, names: .off).columns(inSection: 0) == 1)
    }

    @Test func targetRoundTrips() {
        for c in 1...20 {
            let target = GridLayout.target(columns: c, width: 1200, gap: m.photoGap, edge: m.photoEdge)
            #expect(GridLayout.columns(width: 1200, target: target, gap: m.photoGap, edge: m.photoEdge) == c)
        }
    }

    @Test func squareSlots() {
        for names in [GridNames.off, .photo, .below] {
            let grid = GridLayout(sections: [photos(100)], width: 1000, target: 200, names: names)
            let slot = grid.slotWidth(inSection: 0), columns = grid.columns(inSection: 0)
            let picture = grid.pictureFrame(of: 0)
            #expect(picture.width == slot)
            #expect(picture.height == slot)
            let extra = names == .below ? m.belowText : 0
            #expect(grid.frame(of: columns).minY - grid.frame(of: 0).minY == slot + extra + m.photoGap)
        }
    }

    @Test func twoSectionsWithHeaders() {
        let grid = GridLayout(sections: [folders(5, title: "Folders"), photos(40, title: "Photos · 40")],
                              width: 1200, target: 200, names: .off)
        let header0 = try! #require(grid.headerFrame(ofSection: 0))
        #expect(header0.minY == m.top)
        #expect(grid.frame(of: 0).minY >= header0.maxY)
        #expect(grid.columns(inSection: 0)
                == GridLayout.columns(width: 1200, target: 200 * m.collectionScale, gap: m.collectionGap, edge: m.collectionEdge))
        let header1 = try! #require(grid.headerFrame(ofSection: 1))
        #expect(header1.minY >= grid.frame(of: 4).maxY)
        #expect(grid.frame(of: 5).minY >= header1.maxY)
        #expect(grid.section(of: 4) == 0)
        #expect(grid.section(of: 5) == 1)
        #expect(grid.footerFrame.minY >= grid.frame(of: 44).maxY)
        #expect(grid.contentHeight == grid.footerFrame.maxY)
        #expect(grid.count == 45)
    }

    @Test func noHeaderForSingleSection() {
        let grid = GridLayout(sections: [photos(10)], width: 800, target: 200, names: .off)
        #expect(grid.headerFrame(ofSection: 0) == nil)
        #expect(grid.frame(of: 0).minY == m.top)
    }

    @Test func visibleRangeAcrossSections() {
        let grid = GridLayout(sections: [folders(10, title: "Folders"), photos(400, title: "Photos")],
                              width: 1000, target: 100, names: .off)
        let fc = grid.columns(inSection: 0), pc = grid.columns(inSection: 1)
        let lastFolderRow = grid.frame(of: 9), firstPhoto = grid.frame(of: 10)
        let rect = CGRect(x: 0, y: lastFolderRow.midY, width: 1000, height: firstPhoto.maxY + 1 - lastFolderRow.midY)
        let range = grid.indices(in: rect, margin: 0)
        #expect(range.lowerBound == (9 / fc) * fc)
        #expect(range.upperBound >= 10 + pc)
        #expect((range.upperBound - 10) % pc == 0)
        #expect(GridLayout(sections: [], width: 1000, target: 100, names: .off).indices(in: rect, margin: 0).isEmpty)
    }

    @Test func indexAtPointMissesGapsAndHeaders() {
        let grid = GridLayout(sections: [folders(3, title: "Folders"), photos(20, title: "Photos")],
                              width: 1000, target: 200, names: .off)
        #expect(grid.index(at: CGPoint(x: grid.frame(of: 1).midX, y: grid.frame(of: 1).midY)) == 1)
        #expect(grid.index(at: CGPoint(x: grid.frame(of: 7).midX, y: grid.frame(of: 7).midY)) == 7)
        let header = grid.headerFrame(ofSection: 1)!
        #expect(grid.index(at: CGPoint(x: 10, y: header.midY)) == nil)
        let gapX = grid.frame(of: 0).maxX + m.collectionGap / 2
        #expect(grid.index(at: CGPoint(x: gapX, y: grid.frame(of: 0).midY)) == nil)
        #expect(grid.index(at: CGPoint(x: 5, y: grid.frame(of: 0).midY)) == nil)   // the collections' edge
    }

    @Test func neighbourAcrossSections() {
        let grid = GridLayout(sections: [folders(7, title: "Folders"), photos(50, title: "Photos")],
                              width: 1200, target: 150, names: .off)
        let fc = grid.columns(inSection: 0), pc = grid.columns(inSection: 1)
        let lastFolder = 6, firstOfLastFolderRow = (6 / fc) * fc
        let down = try! #require(grid.neighbour(of: lastFolder, .down))
        #expect(grid.section(of: down) == 1)
        #expect(down < 7 + pc)
        let midX = grid.frame(of: lastFolder).midX
        let nearest = (7..<(7 + pc)).min { abs(grid.frame(of: $0).midX - midX) < abs(grid.frame(of: $1).midX - midX) }
        #expect(down == nearest)
        let up = try! #require(grid.neighbour(of: 7, .up))
        #expect(up >= firstOfLastFolderRow && up <= 6)
        #expect(grid.neighbour(of: fc - 1, .right) == fc)
        #expect(grid.neighbour(of: 0, .left) == nil)
        #expect(grid.neighbour(of: 56, .right) == nil)
        #expect(grid.neighbour(of: 0, .up) == nil)
    }

    @Test func namesHiddenOnSmallSlots() {
        #expect(!GridLayout(sections: [photos(10)], width: 1000, target: 60, names: .photo).showsNames(inSection: 0))
        #expect(GridLayout(sections: [photos(10)], width: 1000, target: 220, names: .photo).showsNames(inSection: 0))
    }

    @Test func namesCycle() {
        #expect(GridNames.off.next == .photo)
        #expect(GridNames.photo.next == .below)
        #expect(GridNames.below.next == .off)
    }

    // MARK: Folder card styles

    @Test func posterReservesItsBand() {
        let grid = GridLayout(sections: [folders(10)], width: 1000, target: 100, names: .off)
        let slot = grid.slotWidth(inSection: 0)
        #expect(grid.frame(of: 0).height == slot + GridLayout.bandHeight(width: slot))
        #expect(GridLayout.bandHeight(width: 180) == 20)    // name line only
        #expect(GridLayout.bandHeight(width: 232) == 35)    // name and facts
        #expect(GridLayout.bandHeight(width: 199.5) == 20)
        #expect(GridLayout.bandHeight(width: 200) == 35)
        // Whatever the name mode: the band does not depend on it.
        let below = GridLayout(sections: [folders(10)], width: 1000, target: 100, names: .below)
        #expect(below.frame(of: 0).height == grid.frame(of: 0).height)
    }

    @Test func photosKeepTheirLayoutInAnyStyle() {
        let a = GridLayout(sections: [photos(100)], width: 1000, target: 200, names: .below)
        for style in CardStyle.allCases {
            #expect(GridLayout(sections: [photos(100)], width: 1000, target: 200, names: .below, style: style) == a)
        }
    }

    @Test func cardsAreThreeHundredWide() {
        let grid = GridLayout(sections: [folders(10)], width: 960, target: 220, names: .off, style: .cards)
        #expect(grid.columns(inSection: 0) == 3)
        #expect(grid.slotWidth(inSection: 0) == 300)
        #expect(grid.frame(of: 0).height == 92)
        #expect(grid.frame(of: 1).minX - grid.frame(of: 0).maxX == m.cardGap)
        #expect(grid.pictureFrame(of: 0).size == CGSize(width: 92, height: 92))
        #expect(grid.index(at: CGPoint(x: grid.frame(of: 4).midX, y: grid.frame(of: 4).midY)) == 4)
        let wide = GridLayout(sections: [folders(10)], width: 1400, target: 220, names: .off, style: .cards)
        #expect(wide.slotWidth(inSection: 0) >= 300)
        #expect(abs(wide.frame(of: wide.columns(inSection: 0) - 1).maxX - (1400 - m.collectionEdge)) <= 0.5)
    }

    @Test func listRowsAre44() {
        let grid = GridLayout(sections: [folders(10)], width: 800, target: 220, names: .off, style: .list)
        #expect(grid.columns(inSection: 0) == 1)
        #expect(grid.frame(of: 0).height == 44)
        #expect(grid.frame(of: 0).width == 800)
        #expect(grid.frame(of: 1).minY - grid.frame(of: 0).minY == 44)
        #expect(grid.pictureFrame(of: 0) == CGRect(x: 4, y: 4, width: 36, height: 36))
    }

    @Test func narrowColumnIsPosters() {
        let posters = GridLayout(sections: [folders(5)], width: 300, target: 220, names: .off)
        for style in CardStyle.allCases {
            #expect(GridLayout(sections: [folders(5)], width: 300, target: 220, names: .off, style: style) == posters)
        }
        #expect(GridLayout(sections: [folders(5)], width: 320, target: 220, names: .off, style: .list).columns(inSection: 0) == 1)
    }

    @Test func stylesMixWithPhotos() {
        let grid = GridLayout(sections: [folders(3, title: "Folders"), photos(20, title: "Photos")],
                              width: 900, target: 200, names: .off, style: .list)
        #expect(grid.frame(of: 3).minY >= grid.frame(of: 2).maxY)
        #expect(grid.section(of: 3) == 1)
        #expect(grid.indices(in: CGRect(x: 0, y: 0, width: 900, height: 2000), margin: 0) == 0..<23)
    }
}
