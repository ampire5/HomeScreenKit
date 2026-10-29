import Testing
import Foundation
@testable import FilmstripModel

private let h = 68.0
private let stripWidth = 1200.0

private func layout(_ n: Int, length: Double = stripWidth, maxAspect: Double = 1.5,
                    aspects: [Double?] = []) -> FilmstripLayout {
    FilmstripLayout(itemCount: n, length: length, thickness: h, maxAspect: maxAspect, aspects: aspects)
}

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

@Test func manyItemsUseNarrowCells() {
    let l = layout(1000)
    #expect(l.cellLength == 0.5625 * h)
    let gap = FilmstripLayout.gapRatio * h
    let expected = Int((stripWidth / (l.cellLength + gap)).rounded(.up)) + 2
    let count = l.cells(offset: l.centre(of: 500), current: 500, expansion: 0).count
    #expect(abs(count - expected) <= 1, "\(count) cells, expected \(expected) ± 1")
    let big = layout(10_000)
    #expect(big.cells(offset: big.centre(of: 5000), current: 5000, expansion: 0).count == count)
}

@Test func fewItemsWidenUpToMax() {
    #expect(layout(3).cellLength == 1.5 * h)
    #expect(layout(20).cellLength == 60)
    #expect(layout(3, maxAspect: 0.5625).cellLength == 0.5625 * h)
}

@Test func cellNeverWiderThanPhoto() {
    let l = layout(3, aspects: [1.5, 0.75, nil])
    #expect(l.narrowLength(of: 1) == 0.75 * h)
    #expect(l.narrowLength(of: 2) == l.cellLength)
    #expect(l.narrowLength(of: 0) == l.cellLength)
}

@Test func currentCentredAndExpanded() throws {
    var aspects = [Double?](repeating: nil, count: 100)
    aspects[5] = 1.5
    let l = layout(100, aspects: aspects)
    let cells = l.cells(offset: l.centre(of: 5), current: 5, expansion: 1)
    let current = try #require(cells.first { $0.item == 5 })
    #expect(near(current.length, 1.5 * h))
    #expect(near(current.start + current.length / 2, stripWidth / 2))
    #expect(current.range == 5..<6)
    func cell(_ item: Int) throws -> FilmstripCell { try #require(cells.first { $0.item == item }) }
    let padding = FilmstripLayout.currentPaddingRatio * h, gap = FilmstripLayout.gapRatio * h
    #expect(near(current.start - (try cell(4)).start - (try cell(4)).length, padding))
    #expect(near((try cell(6)).start - current.start - current.length, padding))
    #expect(near((try cell(4)).start - (try cell(3)).start - (try cell(3)).length, gap))
    #expect(near((try cell(7)).start - (try cell(6)).start - (try cell(6)).length, gap))
}

@Test func expansionUnknownCurrentIsThreeTwo() throws {
    let l = layout(100)
    let cells = l.cells(offset: l.centre(of: 50), current: 50, expansion: 1)
    let current = try #require(cells.first { $0.item == 50 })
    #expect(near(current.length, FilmstripLayout.unknownCurrentAspect * h))
    let half = l.cells(offset: l.centre(of: 50), current: 50, expansion: 0.5)
    let between = try #require(half.first { $0.item == 50 })
    #expect(near(between.length, (l.cellLength + 1.5 * h) / 2))
    #expect(near(between.start + between.length / 2, stripWidth / 2))
}

@Test func fewItemsClusterAroundCentre() {
    let l = layout(3)
    let cells = l.cells(offset: l.centre(of: 1), current: 1, expansion: 0)
    #expect(cells.map(\.item) == [0, 1, 2])
    for c in cells { #expect(c.start > 0 && c.start + c.length < stripWidth, "\(c)") }
    let expanded = l.cells(offset: l.centre(of: 1), current: 1, expansion: 1)
    for c in expanded { #expect(c.start > 0 && c.start + c.length < stripWidth, "\(c)") }
}

@Test func itemAtBaseIsNearestAndClamped() {
    let l = layout(100)
    #expect(l.item(atBase: l.centre(of: 7) + 0.4 * l.cellLength) == 7)
    #expect(l.item(atBase: l.centre(of: 7) - 0.4 * l.cellLength) == 7)
    #expect(l.item(atBase: -500) == 0)
    #expect(l.item(atBase: l.centre(of: 99) + 500) == 99)
    var aspects = [Double?](repeating: nil, count: 100)
    aspects[3] = 0.2
    let mixed = layout(100, aspects: aspects)
    for f in [0, 2, 3, 4, 50, 99] { #expect(mixed.item(atBase: mixed.centre(of: f)) == f, "\(f)") }
    #expect(mixed.item(atBase: mixed.centre(of: 4) + 0.4 * mixed.cellLength) == 4)
}

@Test func centresAreNarrowCellsAndGaps() {
    var aspects = [Double?](repeating: nil, count: 10)
    aspects[1] = 0.25
    let l = layout(10, aspects: aspects)
    let gap = FilmstripLayout.gapRatio * h
    #expect(near(l.centre(of: 0), l.cellLength / 2))
    #expect(near(l.centre(of: 1), l.cellLength + gap + 0.25 * h / 2))
    #expect(near(l.centre(of: 2), l.cellLength + gap + 0.25 * h + gap + l.cellLength / 2))
}

@Test func offsetRangeEnds() {
    let l = layout(100)
    #expect(l.offsetRange == l.centre(of: 0)...l.centre(of: 99))
}

@Test func emptyAndSingleItemCells() throws {
    let empty = layout(0)
    #expect(empty.cellLength == 0)
    #expect(empty.cells(offset: 0, current: 0, expansion: 1) == [])
    #expect(empty.item(atBase: 0) == nil)
    let one = layout(1)
    let cells = one.cells(offset: one.centre(of: 0), current: 0, expansion: 0)
    #expect(cells.count == 1)
    let cell = try #require(cells.first)
    #expect(near(cell.start + cell.length / 2, stripWidth / 2))
    #expect(one.offsetRange == one.centre(of: 0)...one.centre(of: 0))
}

@Test func lengthChangeKeepsCentreItem() {
    let old = layout(500), f = 321
    let new = layout(500, length: 800)
    #expect(old.item(atBase: old.centre(of: f)) == f)
    #expect(new.item(atBase: new.centre(of: f)) == f)
    let few = layout(12), wide = layout(12, length: 2400)
    #expect(few.cellLength != wide.cellLength)
    #expect(wide.item(atBase: wide.centre(of: 5)) == 5)
}

@Test func changedItemCountKeepsCentreItem() {
    let old = layout(20), f = 13
    let new = layout(70)
    #expect(old.cellLength != new.cellLength)
    #expect(new.item(atBase: new.centre(of: f)) == f)
}

@Test func aspectsArrivingKeepCentreItem() {
    let old = layout(200), f = 120
    let aspects: [Double?] = (0..<200).map { $0 % 3 == 0 ? 0.3 : ($0 % 3 == 1 ? 1.5 : nil) }
    let new = layout(200, aspects: aspects)
    #expect(old.centre(of: f) != new.centre(of: f))
    #expect(new.item(atBase: new.centre(of: f)) == f)
}

@Test func fadeLengthIsAShareOfTheHeight() {
    #expect(layout(10).fadeLength == 0.85 * h)
}

private func medianMicroseconds(_ body: () -> Void) -> Double {
    var times: [Double] = []
    for _ in 0..<100 {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1000)
    }
    return times.sorted()[50]
}

@Test func windowIsConstantTime() {
    func cost(_ n: Int, mixed: Bool) -> Double {
        var aspects = mixed ? [Double?](repeating: nil, count: n) : []
        if mixed { aspects[10] = 0.3 }
        let strip = layout(n, aspects: aspects)
        let current = n * 3 / 5
        let offset = strip.centre(of: current)
        return medianMicroseconds { _ = strip.cells(offset: offset, current: current, expansion: 1) }
    }
    // Intel CI under Rosetta measured 56.625 µs against the former 50 µs absolute limit.
    // A 100× larger list must stay within 4× the lookup cost: this catches a full-list scan
    // without turning the runner's speed into an algorithmic regression.
    for mixed in [false, true] {
        let small = cost(10_000, mixed: mixed)
        let large = cost(1_000_000, mixed: mixed)
        #expect(large < small * 4, "mixed=\(mixed): \(small) → \(large) µs")
    }
}

/// A list that grew or was re-read keeps its items' pictures and the strip's centre: each old index's place in
/// the new list, by URL; items that went have none.
@Test func itemsIndexMapFollowsTheItems() {
    let urls = (0..<6).map { URL(fileURLWithPath: "/p/\($0).jpg") }
    let grown = FilmstripItems.indexMap(from: Array(urls.prefix(3)), to: urls)
    #expect(grown == [0: 0, 1: 1, 2: 2])
    let inserted = FilmstripItems.indexMap(from: [urls[0], urls[2], urls[4]], to: urls)
    #expect(inserted == [0: 0, 1: 2, 2: 4])
    let removed = FilmstripItems.indexMap(from: urls, to: [urls[5], urls[1]])
    #expect(removed == [1: 1, 5: 0])
    #expect(FilmstripItems.indexMap(from: urls, to: []).isEmpty)
    #expect(FilmstripItems.indexMap(from: [], to: urls).isEmpty)
}

/// The edges fade only where more cells go on past them, and never over the current cell.
@Test func fadesOnlyWhereTheStripGoesOn() {
    let l = layout(100), fade = 0.85 * h
    // At the first item: nothing before it, so no fade on the left.
    let first = l.cells(offset: l.centre(of: 0), current: 0, expansion: 1)
    #expect(l.fades(cells: first, current: 0) == (start: 0, end: fade))
    let last = l.cells(offset: l.centre(of: 99), current: 99, expansion: 1)
    #expect(l.fades(cells: last, current: 99) == (start: fade, end: 0))
    let middle = l.cells(offset: l.centre(of: 50), current: 50, expansion: 1)
    #expect(l.fades(cells: middle, current: 50) == (start: fade, end: fade))
    // A few items that fit: no fade at all.
    let few = layout(3)
    #expect(few.fades(cells: few.cells(offset: few.centre(of: 1), current: 1, expansion: 1), current: 1) == (start: 0, end: 0))
    // A narrow strip: the fade stops at the current cell.
    let narrow = layout(100, length: 160)
    let cells = narrow.cells(offset: narrow.centre(of: 50), current: 50, expansion: 1)
    let current = cells.first { $0.item == 50 }!
    let fades = narrow.fades(cells: cells, current: 50)
    #expect(fades.start == current.start && fades.end == 160 - current.start - current.length)
    #expect(narrow.fades(cells: [], current: 0) == (start: 0, end: 0))
}

@Test func emptyAndSingleItem() {
    let empty = FilmstripLayout(itemCount: 0, length: 800, thickness: 68, maxAspect: 1.5, aspects: [])
    #expect(empty.cells(offset: 0, current: 0, expansion: 1).isEmpty && empty.item(atBase: 0) == nil)
    let one = FilmstripLayout(itemCount: 1, length: 800, thickness: 68, maxAspect: 1.5, aspects: [1.5])
    #expect(one.cells(offset: one.centre(of: 0), current: 0, expansion: 1).map(\.item) == [0])
    #expect(one.fades(cells: one.cells(offset: one.centre(of: 0), current: 0, expansion: 1), current: 0) == (0, 0))
}

@Test func axisDefaultsToHorizontal() {
    #expect(FilmstripLayout(itemCount: 3, length: 800, thickness: 68, maxAspect: 1.5, aspects: []).axis == .horizontal)
}

/// Two pages side by side: both cells current, each at its own proportions, the plain gap between them and the
/// current padding outside, the pair's middle at the strip's centre; one item as a run is the single current cell.
@Test func runOfCurrentItemsExpandsTogether() throws {
    var aspects = [Double?](repeating: nil, count: 100)
    aspects[10] = 0.7
    aspects[11] = 0.75
    let l = layout(100, aspects: aspects)
    let pair = 10..<12
    let cells = l.cells(offset: l.centre(of: pair), current: pair, expansion: 1)
    func cell(_ item: Int) throws -> FilmstripCell { try #require(cells.first { $0.item == item }) }
    let a = try cell(10), b = try cell(11)
    let padding = FilmstripLayout.currentPaddingRatio * h, gap = FilmstripLayout.gapRatio * h
    #expect(near(a.length, 0.7 * h) && near(b.length, 0.75 * h))
    #expect(near(b.start - a.start - a.length, gap))
    #expect(near((a.start + b.start + b.length) / 2, stripWidth / 2))
    #expect(near(a.start - (try cell(9)).start - (try cell(9)).length, padding))
    #expect(near((try cell(12)).start - b.start - b.length, padding))
    #expect(near((try cell(13)).start - (try cell(12)).start - (try cell(12)).length, gap))
    // Narrow (a moving strip): the run is the base line, its middle between the two cells.
    let narrow = l.cells(offset: l.centre(of: pair), current: pair, expansion: 0)
    let na = try #require(narrow.first { $0.item == 10 }), nb = try #require(narrow.first { $0.item == 11 })
    #expect(near((na.start + nb.start + nb.length) / 2, stripWidth / 2))
    #expect(near(l.centre(of: pair), (l.centre(of: 10) + l.centre(of: 11)) / 2))
    // One item as a run is the single current cell, to the point.
    #expect(l.cells(offset: l.centre(of: 10), current: 10..<11, expansion: 0.6)
            == l.cells(offset: l.centre(of: 10), current: 10, expansion: 0.6))
    #expect(l.centre(of: 10..<11) == l.centre(of: 10))
    // The fade never covers either page.
    let short = layout(100, length: 140, aspects: aspects)
    let shortCells = short.cells(offset: short.centre(of: pair), current: pair, expansion: 1)
    let fades = short.fades(cells: shortCells, current: pair)
    let first = try #require(shortCells.first { $0.item == 10 }), last = try #require(shortCells.last { $0.item == 11 })
    #expect(fades.start <= max(0, first.start) && fades.end <= max(0, 140 - last.start - last.length))
}

/// A run wider than the strip grows only as far as the strip allows; items outside the list are ignored.
@Test func runNeverOutgrowsTheStrip() throws {
    let l = layout(10, length: 200, aspects: [Double?](repeating: 2.5, count: 10))
    let cells = l.cells(offset: l.centre(of: 4..<6), current: 4..<6, expansion: 1)
    let a = try #require(cells.first { $0.item == 4 }), b = try #require(cells.first { $0.item == 5 })
    #expect(near(b.start + b.length - a.start, 200))
    #expect(near(a.length, b.length))
    let clipped = l.cells(offset: l.centre(of: 9), current: 9..<11, expansion: 1)
    #expect(clipped == l.cells(offset: l.centre(of: 9), current: 9, expansion: 1))
    #expect(l.centre(of: 20..<22) == 0)
}
