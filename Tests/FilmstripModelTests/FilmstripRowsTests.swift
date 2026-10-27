import Testing
import Foundation
@testable import FilmstripModel

private func rows(_ count: Int, aspects: [Double?] = [], length: Double = 600) -> FilmstripRows {
    FilmstripRows(itemCount: count, aspects: aspects, length: length, width: 300, rowPicture: 96,
                  currentPicture: 280, cardHeight: 120)
}

/// Every picture is whole at the row's width; a portrait one fits a square, so one tall file does not take the screen.
@Test func wholePictures() {
    let strip = rows(4, aspects: [16.0 / 9, 4.0 / 3, 9.0 / 16, nil])
    let heights = (0..<4).map { strip.plainLength(of: $0) }
    #expect(heights.map { ($0 * 100).rounded() / 100 } == [54, 72, 96, 54])
    let shown = strip.rows(offset: strip.centre(of: 1), current: 1, expansion: 0)
    let portrait = shown.first { $0.item == 2 }!
    #expect(abs(portrait.picture.width - 54) < 0.01 && abs(portrait.picture.height - 96) < 0.01)
}

/// The browsed row: its picture at `currentPicture` wide, the card under it.
@Test func currentRowHasCard() {
    let strip = rows(5)
    let shown = strip.rows(offset: strip.centre(of: 2), current: 2, expansion: 1)
    let current = shown.first { $0.item == 2 }!
    #expect(abs(current.length - (157.5 + 120)) < 0.01)
    #expect(abs(current.picture.width - 280) < 0.01 && abs(current.picture.height - 157.5) < 0.01)
    // Expansion 0: a plain row.
    let plain = strip.rows(offset: strip.centre(of: 2), current: 2, expansion: 0).first { $0.item == 2 }!
    #expect(abs(plain.length - 54) < 0.01)
}

@Test func centreRoundTrip() {
    let strip = rows(50, aspects: (0..<50).map { $0 % 3 == 0 ? 9.0 / 16 : $0 % 3 == 1 ? 4.0 / 3 : nil })
    for item in 0..<50 { #expect(strip.item(atBase: strip.centre(of: item)) == item) }
    #expect(strip.item(atBase: -1000) == 0)
    #expect(strip.item(atBase: 1e6) == 49)
}

@Test func offsetRange() {
    let one = rows(1)
    #expect(one.offsetRange == one.centre(of: 0)...one.centre(of: 0))
    let many = rows(20)
    #expect(many.offsetRange == many.centre(of: 0)...many.centre(of: 19))
}

/// Only what is on screen, plus one row beyond each edge; the browsed row is centred on the strip.
@Test func visibleOnly() {
    let strip = rows(500)
    let shown = strip.rows(offset: strip.centre(of: 250), current: 250, expansion: 1)
    #expect(shown.count < 30)
    #expect(shown.dropFirst().dropLast().allSatisfy { $0.start + $0.length >= 0 && $0.start <= 600 })
    let current = shown.first { $0.item == 250 }!
    #expect(abs(current.start + current.length / 2 - 300) < 0.01)
    #expect(zip(shown, shown.dropFirst()).allSatisfy { $0.item + 1 == $1.item && $0.start + $0.length <= $1.start })
}

/// The edges fade only where the strip goes on, and never over the browsed row.
@Test func fadesNeverOverCurrent() {
    let strip = rows(100)
    let first = strip.rows(offset: strip.centre(of: 0), current: 0, expansion: 1)
    #expect(strip.fades(rows: first, current: 0).start == 0)
    let last = strip.rows(offset: strip.centre(of: 99), current: 99, expansion: 1)
    #expect(strip.fades(rows: last, current: 99).end == 0)
    let middle = strip.rows(offset: strip.centre(of: 50), current: 50, expansion: 1)
    let fades = strip.fades(rows: middle, current: 50)
    let current = middle.first { $0.item == 50 }!
    #expect(fades.start > 0 && fades.start <= current.start)
    #expect(fades.end > 0 && fades.end <= 600 - current.start - current.length)
}

/// No rows, or one: nothing breaks.
@Test func rowsSingleAndEmpty() {
    let none = rows(0)
    #expect(none.rows(offset: 0, current: 0, expansion: 1).isEmpty)
    #expect(none.item(atBase: 0) == nil)
    #expect(none.offsetRange == 0...0)
    let one = rows(1)
    #expect(one.rows(offset: one.centre(of: 0), current: 0, expansion: 1).map(\.item) == [0])
}

/// Every row has its caption under its picture; the browsed one a larger caption, and the card under that.
@Test func captionUnderPicture() {
    let strip = FilmstripRows(itemCount: 5, aspects: [], length: 600, width: 300, rowPicture: 160, currentPicture: 284,
                              cardHeight: 40, captionHeight: 32, currentCaptionHeight: 38)
    let shown = strip.rows(offset: strip.centre(of: 2), current: 2, expansion: 1)
    let plain = shown.first { $0.item == 1 }!
    #expect(abs(plain.length - (90 + 32)) < 0.01)
    #expect(abs(plain.caption.minY - 90) < 0.01 && abs(plain.caption.height - 32) < 0.01 && abs(plain.caption.width - 160) < 0.01)
    let current = shown.first { $0.item == 2 }!
    #expect(abs(current.length - (159.75 + 38 + 40)) < 0.01)
    #expect(abs(current.caption.minY - 159.75) < 0.01 && abs(current.caption.height - 38) < 0.01)
    #expect(abs(strip.plainLength(of: 1) - 122) < 0.01)
}
