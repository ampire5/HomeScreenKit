import Foundation

/// How far a grid was scrolled, kept so it survives a changed listing (a session's tab after a relaunch): the first
/// fully visible entry, how far below the view's top its card starts, and its index in the order it was in. An entry
/// gone since takes the one now at its index (the nearest by sort position); no entries, the top.
public struct BrowserAnchor: Codable, Equatable, Sendable {
    public var id: String
    /// Points from the view's top down to the card's top.
    public var offset: Double
    /// The entry's index in the order on screen when it was taken.
    public var index: Int

    public init(id: String, offset: Double, index: Int) {
        self.id = id
        self.offset = offset
        self.index = index
    }

    /// The index to scroll to among `count` entries (`index(of:)`: an id's index in them): the entry's, else its old
    /// index (the last past the end); nil with no entries.
    public func target(count: Int, index of: (String) -> Int?) -> Int? {
        guard count > 0 else { return nil }
        return of(id) ?? min(max(index, 0), count - 1)
    }
}
