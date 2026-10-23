import Foundation

/// What Home's toolbar pill and its popover show of the thumbnails being prepared (thumbs-ahead spec, "Пилюля в
/// тулбаре"). The app builds the texts; the kit draws what it is given.
public struct ThumbsProgressState: Equatable, Sendable {
    /// One line of the popover: a stage's name, and how far it is ("In view 24 / 24" over its bar).
    public struct Row: Equatable, Sendable {
        public var title: String
        public var done: Int
        public var total: Int

        public init(title: String, done: Int, total: Int) {
            self.title = title
            self.done = done
            self.total = total
        }

        /// The bar's share, 0…1; an empty stage shows an empty bar.
        public var fraction: Double { total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0 }
    }

    /// The current stage's share, 0…1: the ring.
    public var fraction: Double
    /// The pill's text: "Thumbnails 120 / 480", "Subfolders 5 / 48", "Paused · 120 / 480".
    public var text: String
    /// Either pause (the user's or the viewer's): a grey ring with the play glyph.
    public var paused: Bool
    /// The popover's lines, in order.
    public var rows: [Row]
    /// The popover's line under the rows: "Paused", "Paused while you browse", "Waiting for the share"…; nil: none.
    public var pauseNote: String?
    /// The user's own pause (the popover's button then reads "Resume"); the viewer's pause leaves it at "Pause".
    public var pausedByUser: Bool
    /// Whether something is being prepared now. False: all is done (or nothing was asked); the pill stays out (or
    /// goes out), and the popover (View › Thumbnails…) still shows these counts.
    public var working: Bool
    /// A subtree is being prepared on the user's command (Prepare subfolders, a card's Prepare thumbnails…): the
    /// popover's second button reads "Stop preparing" and stops it.
    public var subtreeRunning: Bool

    public init(fraction: Double, text: String, paused: Bool = false, rows: [Row] = [], pauseNote: String? = nil,
                pausedByUser: Bool = false, working: Bool = true, subtreeRunning: Bool = false) {
        self.fraction = fraction
        self.text = text
        self.paused = paused
        self.rows = rows
        self.pauseNote = pauseNote
        self.pausedByUser = pausedByUser
        self.working = working
        self.subtreeRunning = subtreeRunning
    }

    /// What the popover shows before the app gave any counts for the folder: nothing to do, the three stages at zero.
    public static let idle = ThumbsProgressState(
        fraction: 0, text: "",
        rows: [Row(title: "In view", done: 0, total: 0), Row(title: "Rest of folder", done: 0, total: 0),
               Row(title: "Subfolders", done: 0, total: 0)],
        working: false)
}
