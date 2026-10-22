import Foundation

/// What a folder or archive card tells about its contents: numbers, dates, how much was seen. The app fills it as it
/// learns (it comes after the listing, like the pictures); the views draw it and `CardSummaryText` makes the words.
public struct CardSummary: Equatable, Sendable {
    public enum Problem: Sendable {
        /// The folder or archive cannot be read.
        case broken
        /// Its volume is not there now.
        case offline
    }

    /// Photos directly in the folder.
    public var photos: Int?
    /// Subfolders.
    public var folders: Int?
    /// Photos in the subfolders, as far as their own summaries are known.
    public var insidePhotos: Int?
    /// Some subfolders have no summary yet: `insidePhotos` is at least that.
    public var insideIncomplete: Bool
    public var bytes: Int64?
    /// The oldest and the newest photo's date.
    public var first: Date?
    public var last: Date?
    /// 12 bins over `first`…`last`; each bin's share of the photos, the bins summing to about 255 (all photos on one
    /// date: one bin 255). The views scale the bars to the largest bin.
    public var histogram: [UInt8]
    /// 0…1: how much of the folder was viewed.
    public var viewed: Double?
    /// Viewed to the end.
    public var done: Bool
    /// Photos new since the last visit; 0 is none.
    public var new: Int
    /// A two-page spread (⧉) and right-to-left reading (RTL).
    public var twoPages: Bool
    public var rightToLeft: Bool
    public var problem: Problem?

    public init(photos: Int? = nil, folders: Int? = nil, insidePhotos: Int? = nil, insideIncomplete: Bool = false,
                bytes: Int64? = nil, first: Date? = nil, last: Date? = nil, histogram: [UInt8] = [], viewed: Double? = nil,
                done: Bool = false, new: Int = 0, twoPages: Bool = false, rightToLeft: Bool = false,
                problem: Problem? = nil) {
        self.photos = photos
        self.folders = folders
        self.insidePhotos = insidePhotos
        self.insideIncomplete = insideIncomplete
        self.bytes = bytes
        self.first = first
        self.last = last
        self.histogram = histogram
        self.viewed = viewed
        self.done = done
        self.new = new
        self.twoPages = twoPages
        self.rightToLeft = rightToLeft
        self.problem = problem
    }
}
