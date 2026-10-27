import Testing
import Foundation
@testable import FilmstripModel

// A hundred items at 68 pt in 1200 pt: narrow 9:16 cells (38.25 pt) and a 1.904 pt gap, 40.154 pt an item.
private let strip = FilmstripLayout(itemCount: 100, length: 1200, thickness: 68, maxAspect: 1.5, aspects: [])
private let pitch = strip.cellLength + strip.gap

private func step(_ scroll: inout FilmstripScroll, _ dx: Double, _ dy: Double = 0, phase: ScrollPhase = .changed,
                  momentum: ScrollPhase = [], layout: FilmstripLayout = strip, current: Int,
                  now: Double = 0) -> FilmstripScroll.Outcome {
    scroll.event(fingerDelta: dx, crossDelta: dy, phase: phase, momentum: momentum, layout: layout, current: current, now: now)
}

private func near(_ a: Double?, _ b: Double, _ tolerance: Double = 0.5) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

/// Fingers moving left take the strip, and so the centre, to the next items, an item's pitch of travel per item
/// (the strip is content that follows the fingers); each item is reported once, as it reaches the centre.
@Test func fingersLeftMoveToNextItems() {
    var scroll = FilmstripScroll()
    #expect(scroll.offset == nil && !scroll.isMoving)
    #expect(step(&scroll, -pitch, phase: .began, current: 10).item == 11)
    #expect(scroll.isMoving)
    #expect(step(&scroll, -pitch, current: 11).item == 12)
    #expect(step(&scroll, -pitch, current: 12).item == 13)
    #expect(near(scroll.offset, strip.centre(of: 10) + 3 * pitch))
    // Less than half a pitch more: still 13, the strip moved.
    #expect(step(&scroll, -0.3 * pitch, current: 13).item == nil)
    #expect(near(scroll.offset, strip.centre(of: 10) + 3.3 * pitch))
}

@Test func reversedDirection() {
    var scroll = FilmstripScroll()
    scroll.direction = .reversed
    #expect(step(&scroll, -pitch, phase: .began, current: 10).item == 9)
    #expect(step(&scroll, -pitch, current: 9).item == 8)
    #expect(step(&scroll, -pitch, current: 8).item == 7)
}

/// A mouse drag carries the strip with the cursor: dragging left by two items brings item 12 to the centre.
@Test func mouseDragFollowsCursor() {
    var scroll = FilmstripScroll()
    #expect(scroll.drag(by: -2 * pitch, layout: strip, current: 10).item == 12)
    #expect(near(scroll.offset, strip.centre(of: 12)))
    #expect(scroll.isMoving)
    #expect(scroll.drag(by: pitch, layout: strip, current: 12).item == 11)
}

/// Past the first or last item a trackpad pulls the strip on at 0.3 of the travel and settles back on the end.
@Test func trackpadRubberBandsAtEnds() throws {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, 10 * pitch, phase: .began, current: 2).item == 0)
    // Two items to the first, eight beyond it at 0.3.
    #expect(near(scroll.offset, strip.centre(of: 0) - 0.3 * 8 * pitch))
    let settled = try #require(scroll.settled(layout: strip))
    #expect(settled.item == 0 && settled.offset == strip.centre(of: 0))
    var end = FilmstripScroll()
    _ = step(&end, -4 * pitch, phase: .began, current: 98)
    #expect(near(end.offset, strip.centre(of: 99) + 0.3 * 3 * pitch))
    #expect(end.settled(layout: strip)?.item == 99)
}

@Test func mouseStopsAtEnds() throws {
    var scroll = FilmstripScroll()
    _ = scroll.drag(by: 10 * pitch, layout: strip, current: 2)
    #expect(scroll.offset == strip.centre(of: 0))
    #expect(scroll.drag(by: -pitch, layout: strip, current: 0).item == 1)   // turning back moves at once
    let settled = try #require(scroll.settled(layout: strip))
    #expect(settled.item == 1)
}

@Test func settlesOnNearest() throws {
    var scroll = FilmstripScroll()
    _ = scroll.drag(by: -(strip.centre(of: 20) - strip.centre(of: 10) + 0.4 * pitch), layout: strip, current: 10)
    let settled = try #require(scroll.settled(layout: strip))
    #expect(settled.item == 20 && settled.offset == strip.centre(of: 20))
    scroll.settle()
    #expect(scroll.offset == nil && !scroll.isMoving && scroll.settled(layout: strip) == nil)
}

/// Momentum after the fingers lift carries the strip on, like a flick; its end commits. The fingers' own end
/// does not: momentum may still follow, and the controller's rest timer commits when none does.
@Test func momentumEndCommits() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, phase: .began, current: 10) == .init(item: 11, commit: false))
    #expect(step(&scroll, -1, phase: .ended, current: 11) == .init(item: nil, commit: false))
    #expect(step(&scroll, -pitch, phase: [], momentum: .began, current: 11) == .init(item: 12, commit: false))
    #expect(step(&scroll, -pitch, phase: [], momentum: .changed, current: 12) == .init(item: 13, commit: false))
    #expect(step(&scroll, 0, phase: [], momentum: .ended, current: 13) == .init(item: nil, commit: true))
    #expect(!scroll.isMoving && !scroll.isScrubbing && scroll.restDeadline == nil)
    #expect(scroll.settled(layout: strip)?.item == 13)
    #expect(!step(&scroll, 0, phase: [], momentum: .ended, current: 13).commit)
}

@Test func cancelledCommits() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, phase: .began, current: 10).item == 11)
    #expect(step(&scroll, 0, phase: .cancelled, current: 11).commit)
    var coast = FilmstripScroll()
    #expect(step(&coast, -pitch, phase: .began, current: 10).item == 11)
    #expect(step(&coast, 0, phase: [], momentum: .cancelled, current: 11).commit)
    // Nothing moved: nothing to commit.
    var idle = FilmstripScroll()
    #expect(step(&idle, 0, phase: .cancelled, current: 10) == .init(item: nil, commit: false))
}

/// Every event while the strip moves puts the rest off; the rest commits once the deadline has passed, also when
/// the strip moved by less than an item (it still has to settle), and an early wake commits nothing.
@Test func restCommitsWithoutMomentum() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, phase: .began, current: 10, now: 1).item == 11)
    #expect(scroll.isScrubbing && scroll.restDeadline == 1 + FilmstripScroll.restDelay)
    #expect(step(&scroll, -1, current: 11, now: 1.1).item == nil)
    #expect(scroll.restDeadline == 1.1 + FilmstripScroll.restDelay)
    let early = scroll.rested(now: 1 + FilmstripScroll.restDelay)
    #expect(!early && scroll.isMoving)
    let due = scroll.rested(now: 1.1 + FilmstripScroll.restDelay)
    #expect(due && !scroll.isMoving && !scroll.isScrubbing && scroll.restDeadline == nil)
    let again = scroll.rested(now: 5)
    #expect(!again)
    var nudge = FilmstripScroll()
    #expect(step(&nudge, -0.3 * pitch, phase: .began, current: 10, now: 1).item == nil)
    #expect(!nudge.isScrubbing && nudge.isMoving && nudge.restDeadline == 1 + FilmstripScroll.restDelay)
    let nudged = nudge.rested(now: 2)
    #expect(nudged && nudge.settled(layout: strip)?.item == 10)
}

/// The gesture's axis is taken from its first few points of travel: a vertical swipe never moves the strip, even
/// where one of its events leans sideways; the next gesture decides afresh.
@Test func verticalIgnored() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -1, 20, phase: .began, current: 10).item == nil)
    #expect(step(&scroll, -200, 5, current: 10).item == nil)
    #expect(step(&scroll, -200, 0, phase: .ended, current: 10).item == nil)
    #expect(step(&scroll, 0, -100, phase: [], momentum: .began, current: 10).item == nil)
    #expect(scroll.offset == nil && !scroll.isMoving)
    #expect(step(&scroll, -pitch, 1, phase: .began, current: 10).item == 11)
}

/// Travel below the lock distance is kept, and applied once the axis is known.
@Test func axisLockedOnce() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, 0, 0, phase: .mayBegin, current: 10).item == nil)
    #expect(step(&scroll, -2, 1, phase: .began, current: 10).item == nil)
    #expect(scroll.offset == nil)
    #expect(step(&scroll, -(pitch - 2), 0, current: 10).item == 11)
    #expect(near(scroll.offset, strip.centre(of: 11)))
    // Once horizontal, a vertical lean does not unlock it.
    #expect(step(&scroll, -pitch, 30, current: 11).item == 12)
}

/// Devices without phases: each event is classified by itself.
@Test func unphasedEventsAreClassifiedOneByOne() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, 0, phase: [], current: 10).item == 11)
    #expect(step(&scroll, -100, 200, phase: [], current: 11).item == nil)
    #expect(step(&scroll, -pitch, 2, phase: [], current: 11).item == 12)
}

/// The current photo moved without the strip (a key, the wheel): the next event starts from it.
@Test func anotherCurrentPhotoReanchors() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, phase: .began, current: 10).item == 11)
    #expect(step(&scroll, -pitch, current: 40).item == 41)
    #expect(near(scroll.offset, strip.centre(of: 41)))
}

/// A press during the momentum or the settling takes over: the rest of that momentum does nothing, the scroll
/// has nothing to commit; the next gesture moves the strip again.
@Test func pressDuringMomentumTakesOver() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, phase: .began, current: 10, now: 1).item == 11)
    #expect(step(&scroll, -pitch, phase: [], momentum: .began, current: 11, now: 1.1).item == 12)
    scroll.takeOver()
    #expect(!scroll.isMoving && !scroll.isScrubbing && scroll.restDeadline == nil)
    #expect(step(&scroll, -pitch, phase: [], momentum: .changed, current: 12, now: 1.2) == .init(item: nil, commit: false))
    #expect(step(&scroll, 0, phase: [], momentum: .ended, current: 12, now: 1.3) == .init(item: nil, commit: false))
    let rested = scroll.rested(now: 9), ended = scroll.end()
    #expect(!rested && !ended)
    scroll.settle()
    #expect(step(&scroll, -pitch, phase: .began, current: 30, now: 10).item == 31)
}

/// `end()` (window resigns key, full screen) commits a scrub that is on, once.
@Test func endCommitsOnce() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, phase: .began, current: 10).item == 11)
    let ended = scroll.end(), endedAgain = scroll.end()
    #expect(ended && !endedAgain && !scroll.isMoving)
}

/// The folder grew (or its aspects or the width changed) while the strip moves: the item at the centre stays.
@Test func itemCountChangeMidGestureKeepsItem() {
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -pitch, phase: .began, current: 10).item == 11)
    let grown = FilmstripLayout(itemCount: 150, length: 1200, thickness: 68, maxAspect: 1.5, aspects: [])
    scroll.layoutChanged(keeping: 11, layout: grown)
    #expect(scroll.offset == grown.centre(of: 11))
    #expect(step(&scroll, -(grown.cellLength + grown.gap), layout: grown, current: 11).item == 12)
    var idle = FilmstripScroll()
    idle.layoutChanged(keeping: 11, layout: grown)
    #expect(idle.offset == nil)
}

@Test func singleItemGestureDoesNothing() {
    let one = FilmstripLayout(itemCount: 1, length: 1200, thickness: 68, maxAspect: 1.5, aspects: [])
    var scroll = FilmstripScroll()
    #expect(step(&scroll, -500, phase: .began, layout: one, current: 0) == .init(item: nil, commit: false))
    #expect(scroll.drag(by: -500, layout: one, current: 0).item == nil)
    #expect(scroll.offset == nil && !scroll.isMoving)
    let empty = FilmstripLayout(itemCount: 0, length: 1200, thickness: 68, maxAspect: 1.5, aspects: [])
    #expect(step(&scroll, -500, phase: .began, layout: empty, current: 0).item == nil)
    #expect(scroll.settled(layout: empty) == nil)
}

/// The controller's sequence, in the model: a gesture across five items scrubs each once, in order, and its
/// momentum's end commits once.
@Test func gestureScrubsEachItemOnceAndCommitsOnce() {
    var scroll = FilmstripScroll()
    var current = 10, items: [Int] = [], commits = 0
    let events: [(Double, ScrollPhase, ScrollPhase)] = [(-0.5 * pitch, .began, [])]
        + Array(repeating: (-0.25 * pitch, .changed, []), count: 8)
        + [(0, .ended, [])]
        + Array(repeating: (-0.25 * pitch, [], .changed), count: 10)
        + [(0, [], .ended)]
    for (dx, phase, momentum) in events {
        let outcome = step(&scroll, dx, phase: phase, momentum: momentum, current: current)
        if let item = outcome.item {
            items.append(item)
            current = item
        }
        if outcome.commit { commits += 1 }
    }
    #expect(items == Array(11...15))
    #expect(commits == 1)
}

/// A motion that starts from two current items at rest (two pages side by side) starts from the middle of the run,
/// where the strip rests, not from the current item's centre: no jump. The middle is in the gap between the two cells,
/// so the item at the centre is the run's other one (the caller has it on screen already); once the caller takes that
/// as current, the strip goes on from where it is and the anchor no longer applies.
@Test func motionStartsFromARunAnchor() {
    let run = strip.centre(of: 10..<12)
    var scroll = FilmstripScroll()
    let first = scroll.drag(by: 0, layout: strip, current: 10, anchor: run)
    #expect(scroll.offset == run)
    #expect(first.item.map { (10..<12).contains($0) } ?? true)
    #expect(scroll.drag(by: -1, layout: strip, current: 11, anchor: strip.centre(of: 40)).item == nil)
    #expect(near(scroll.offset, run + 1, 1e-9))
    var swipe = FilmstripScroll()
    _ = step(&swipe, -0.5 * FilmstripScroll.lockDistance, phase: .began, current: 10)
    _ = swipe.event(fingerDelta: -FilmstripScroll.lockDistance, crossDelta: 0, phase: .changed, momentum: [],
                    layout: strip, current: 10, now: 0, anchor: run)
    #expect(near(swipe.offset, run + 1.5 * FilmstripScroll.lockDistance))
    // Without an anchor: the current item's centre, as before.
    var plain = FilmstripScroll()
    _ = plain.drag(by: 0, layout: strip, current: 10)
    #expect(plain.offset == strip.centre(of: 10))
}

/// Ten items 50 pt apart: a layout that is not `FilmstripLayout`.
private struct EvenTrack: FilmstripTrack {
    var itemCount: Int { 10 }
    var offsetRange: ClosedRange<Double> { 0...450 }
    func centre(of item: Int) -> Double { 50 * Double(item) }
    func item(atBase position: Double) -> Int? { min(max(Int((position / 50).rounded()), 0), 9) }
}

/// The scroll works on any track, not only the filmstrip's own layout (the vertical rows use it too).
@Test func scrollOnAnyTrack() {
    var scroll = FilmstripScroll()
    let outcome = scroll.event(fingerDelta: -60, crossDelta: 0, phase: .changed, momentum: [], layout: EvenTrack(),
                               current: 0, now: 0)
    #expect(outcome.item == 1)
}
