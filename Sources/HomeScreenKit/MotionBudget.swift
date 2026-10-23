import Foundation

/// The time an endless Core Animation loop (a shimmer, a glint, a shine) may run in one go, so that nothing on screen
/// moves for ever: the owner's rule "quiet at rest". Every running loop is redrawn by the window server 60 times a
/// second, whatever the app does meanwhile. The time moving adds up across pauses (the window hidden, the view out of
/// view); once it is spent the owner shows its still look until `reset` (a new wait, a new load). Main thread only.
@MainActor final class MotionBudget {
    var limit: Duration
    /// The time is spent: the owner stops its animation (it asks `update` again, which says no).
    var onSpent: (() -> Void)?
    private var spent: Duration = .zero
    private var since: ContinuousClock.Instant?
    private var end: Task<Void, Never>?

    init(limit: Duration) {
        self.limit = limit
    }

    /// Whether the loop runs now: `wanted` (the owner may move: on screen, no Reduce Motion) and time is left. While it
    /// runs, the clock counts and `onSpent` comes when the time is up; not running, the clock stops.
    func update(wanted: Bool) -> Bool {
        let now = ContinuousClock.now
        if let since {
            spent += now - since
            self.since = nil
        }
        end?.cancel()
        end = nil
        let left = limit - spent
        guard wanted, left > .zero else { return false }
        since = now
        end = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: left)) != nil, let self else { return }
            self.end = nil
            self.onSpent?()
        }
        return true
    }

    /// A new run (a new wait, a new load): the whole time again, the clock stopped.
    func reset() {
        end?.cancel()
        end = nil
        since = nil
        spent = .zero
    }
}
