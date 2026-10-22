/// Scrolling over the thumbnail strip (M2.5 spec §4.3, Photos' filmstrip 2026-10-21): a horizontal trackpad swipe
/// or a mouse drag moves the strip under its fixed centre, and the item that reaches the centre becomes the current
/// one, like a scrub; a vertical swipe does nothing (the photo under the strip does not pan), and a notched wheel steps
/// photos as everywhere. Pure: the strip feeds it the event's deltas and phases, and the controller draws the strip at
/// `offset` and acts on the outcome (`ViewerSession.scrub(to:)` for a new item; for a commit, settles the strip on
/// `settled(layout:)` and ends the scrub).
///
/// `offset` is the base x (`FilmstripLayout`) under the strip's centre while the strip moves, nil while it follows
/// the current item. It starts at the current item's centre — again whenever the current item is not the one reached
/// last (a key or the wheel moved it) — and moves point for point with the fingers or the cursor. Past the first or
/// last item a trackpad pulls it on at `rubberBand` of the travel (and back the same way); a mouse stops there, so
/// turning back moves at once.
///
/// Direction (`FilmstripScrollDirection`): `natural` (the default) takes fingers moving left to the next items, as the
/// three-finger swipe does: the strip is content that follows the fingers. `reversed` moves the other way. `fingerDelta`
/// is the fingers' own movement, whatever "natural scrolling" says (`FingerDirection`). A mouse drag always carries the
/// strip with the cursor.
///
/// A gesture's axis is decided once from its first `lockDistance` points of travel, and its momentum keeps it, so a
/// slightly diagonal swipe neither stutters nor pans; events without phases (no gesture to belong to) are classified
/// one by one. Momentum (the system's; there is none of our own) carries the strip on, like a flick, and its end
/// commits. The fingers' own `.ended` does not commit: the momentum that may follow begins up to ~100 ms later (the
/// wait Chromium allows between the two), so a rest of `restDelay` without events commits a lift without momentum.
///
/// The strip moves (`isMoving`) from its first travel to the commit: the end of the momentum or a cancelled gesture
/// (`Outcome.commit`), the rest (`rested(now:)` once `restDeadline` has passed; every event puts it off, so the
/// controller keeps one timer and re-arms it when it wakes early), or `end()` (the window resigned key, full screen).
/// The scrub is on (`isScrubbing`) from the first new item to that commit. A press on the cells takes over
/// (`takeOver()`): the rest of the gesture's momentum does nothing. `settle()` once the strip sits on an item again
/// hands it back to the current item. Times are seconds on the caller's clock.
public struct FilmstripScroll: Sendable {
    /// What the controller does after an event.
    public struct Outcome: Sendable, Equatable {
        /// A item the selection reached that it was not on before: scrub to it.
        public var item: Int?
        /// The scrub was on and the gesture's momentum ended, or the gesture was cancelled: commit now rather than
        /// after the rest.
        public var commit: Bool

        public init(item: Int?, commit: Bool) {
            self.item = item
            self.commit = commit
        }
    }

    /// Travel (points, on either axis) after which a gesture's axis is decided.
    public static let lockDistance = 4.0
    /// Seconds without a scroll event that commit the scrub: the mouse scrub's rest (`ViewerSession.dwellDelay`).
    public static let restDelay = 0.15

    public var direction = FilmstripScrollDirection.natural
    /// From the first new item the strip brings to the centre to the commit.
    public private(set) var isScrubbing = false
    /// When the rest commits, while the strip moves.
    public private(set) var restDeadline: Double?
    /// The base x under the strip's centre while the strip moves or settles; nil: it follows the current item.
    public var offset: Double? { raw.map(shown) }
    /// A gesture, its momentum or a drag moves the strip.
    public private(set) var isMoving = false

    /// How far a trackpad pulls the strip on past its first or last item, as a share of the travel.
    public static let rubberBand = 0.3

    private enum GestureAxis { case horizontal, vertical }

    /// The gesture's axis, nil until decided (or without a gesture).
    private var axis: GestureAxis?
    /// Travel of the gesture so far, while its axis is still open.
    private var openX = 0.0, openY = 0.0
    /// The offset the travel adds up to, before the rubber band; nil while the strip follows the current item.
    private var raw: Double?
    /// The offset range of the layout `raw` was last moved on (the rubber band's ends).
    private var range: ClosedRange<Double> = 0...0
    /// The item at the centre: the last one reported, or the anchor.
    private var item: Int?
    /// A press took over: the rest of the gesture's momentum is ignored until a new gesture begins.
    private var ignoresMomentum = false

    public init() {}

    /// One precise scroll event over the strip. `fingerDelta`: the fingers' horizontal movement in points (negative =
    /// left); `crossDelta`: the vertical delta (only its size matters). `current`: the session's current item; `now`: the
    /// event's time.
    public mutating func event(fingerDelta: Double, crossDelta: Double, phase: ScrollPhase, momentum: ScrollPhase,
                               layout: FilmstripLayout, current: Int, now: Double) -> Outcome {
        let ends = momentum.contains(.ended) || momentum.contains(.cancelled) || phase.contains(.cancelled)
        if momentum.isEmpty, phase.contains(.began) || phase.contains(.mayBegin) { ignoresMomentum = false }
        if ignoresMomentum, !momentum.isEmpty { return Outcome(item: nil, commit: false) }
        var outcome = Outcome(item: nil, commit: false)
        if let travel = travel(fingerDelta: fingerDelta, crossDelta: crossDelta, phase: phase, momentum: momentum), travel != 0 {
            outcome.item = move(by: direction == .natural ? -travel : travel, rubber: true, layout: layout,
                                current: current)
        }
        guard isMoving else { return outcome }
        if ends {
            outcome.commit = true
            takeOver()
        } else {
            restDeadline = now + Self.restDelay
        }
        return outcome
    }

    /// A mouse drag over the strip moved by `dx` points: the strip follows the cursor, up to its ends.
    public mutating func drag(by dx: Double, layout: FilmstripLayout, current: Int) -> Outcome {
        Outcome(item: move(by: -dx, rubber: false, layout: layout, current: current), commit: false)
    }

    /// Where the strip comes to rest: the item nearest the centre and the offset that centres it; nil while it
    /// follows the current item.
    public func settled(layout: FilmstripLayout) -> (item: Int, offset: Double)? {
        guard let offset, let item = layout.item(atBase: offset) else { return nil }
        return (item, layout.centre(of: item))
    }

    /// The strip sits on an item again: it follows the current item from now on.
    public mutating func settle() {
        raw = nil
        item = nil
        isMoving = false
        isScrubbing = false
        restDeadline = nil
    }

    /// The layout changed (the folder grew, aspects arrived, a resize) while the strip moves or settles: it stays on
    /// `item`, at that item's centre in the new layout.
    public mutating func layoutChanged(keeping item: Int, layout: FilmstripLayout) {
        guard raw != nil, layout.itemCount > 0 else { return }
        let item = min(max(item, 0), layout.itemCount - 1)
        range = layout.offsetRange
        raw = layout.centre(of: item)
        self.item = item
    }

    /// The rest timer woke: true (and the motion is over) once `restDeadline` has passed.
    public mutating func rested(now: Double) -> Bool {
        guard isMoving, let restDeadline, now >= restDeadline else { return false }
        takeOver()
        return true
    }

    /// A press on the cells took over (or the motion committed): nothing is left to commit, and the rest of the
    /// gesture's momentum does nothing.
    public mutating func takeOver() {
        isMoving = false
        isScrubbing = false
        restDeadline = nil
        ignoresMomentum = true
    }

    /// The scrub must commit now (the window resigned key, full screen): true when one was on.
    public mutating func end() -> Bool {
        defer { takeOver() }
        return isScrubbing
    }

    /// The horizontal travel of this event, nil while it adds none (vertical, or axis still open).
    private mutating func travel(fingerDelta: Double, crossDelta: Double, phase: ScrollPhase, momentum: ScrollPhase) -> Double? {
        if phase.isEmpty, momentum.isEmpty {
            // No gesture: this event alone.
            axis = nil
            return abs(fingerDelta) > abs(crossDelta) ? fingerDelta : nil
        }
        if momentum.isEmpty, phase.contains(.began) || phase.contains(.mayBegin) {
            axis = nil
            openX = 0
            openY = 0
        }
        switch axis {
        case .horizontal: return fingerDelta
        case .vertical: return nil
        case nil:
            // Momentum of a gesture whose start was not seen here: this event alone.
            if !momentum.isEmpty { return abs(fingerDelta) > abs(crossDelta) ? fingerDelta : nil }
            openX += fingerDelta
            openY += crossDelta
            guard max(abs(openX), abs(openY)) >= Self.lockDistance else { return nil }
            axis = abs(openX) > abs(openY) ? .horizontal : .vertical
            return axis == .horizontal ? openX : nil
        }
    }

    /// Moves the strip's offset by `dx` points; the new item at the centre, if it is one.
    private mutating func move(by dx: Double, rubber: Bool, layout: FilmstripLayout, current: Int) -> Int? {
        guard layout.itemCount > 1, (0..<layout.itemCount).contains(current) else { return nil }
        range = layout.offsetRange
        // Anchored on the current item, again whenever it is not the one reached last (a key or the wheel moved it).
        if raw == nil || item != current {
            raw = layout.centre(of: current)
            item = current
        }
        var moved = raw! + dx
        if !rubber { moved = min(max(moved, range.lowerBound), range.upperBound) }
        raw = moved
        isMoving = true
        guard let reached = layout.item(atBase: shown(moved)), reached != item else { return nil }
        item = reached
        isScrubbing = true
        return reached
    }

    /// `raw` with the rubber band past the ends.
    private func shown(_ raw: Double) -> Double {
        if raw < range.lowerBound { return range.lowerBound - (range.lowerBound - raw) * Self.rubberBand }
        if raw > range.upperBound { return range.upperBound + (raw - range.upperBound) * Self.rubberBand }
        return raw
    }
}
