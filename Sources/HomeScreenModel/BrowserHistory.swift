import CoreGraphics

/// The browser's Back and Forward, as a web browser's: a move clears Forward. Each place remembers the card that was
/// selected and how far the grid was scrolled, so Back lands where the user left; Up selects the folder it came out of.
public struct BrowserHistory: Sendable {
    public private(set) var current: BrowserLocation
    private var backStack: [BrowserLocation] = []
    private var forwardStack: [BrowserLocation] = []
    private var memory: [BrowserLocation: (selection: String?, scroll: CGFloat)] = [:]
    /// Places in the order they were last remembered: the oldest is forgotten past `memoryLimit`.
    private var remembered: [BrowserLocation] = []

    private static let memoryLimit = 64

    public init(start: BrowserLocation) {
        current = start
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// A move to `location`; the same place is no move.
    public mutating func go(to location: BrowserLocation) {
        guard location != current else { return }
        backStack.append(current)
        forwardStack = []
        current = location
    }

    public mutating func back() -> Bool {
        guard let previous = backStack.popLast() else { return false }
        forwardStack.append(current)
        current = previous
        return true
    }

    public mutating func forward() -> Bool {
        guard let next = forwardStack.popLast() else { return false }
        backStack.append(current)
        current = next
        return true
    }

    /// A move to `parent` (nil: there is none, the places); returns the id to select there: the folder left.
    public mutating func up(parent: BrowserLocation?) -> String? {
        guard let parent, case .folder(let url) = current else { return nil }
        go(to: parent)
        return url.path
    }

    public mutating func remember(selection: String?, scroll: CGFloat) {
        memory[current] = (selection, scroll)
        remembered.removeAll { $0 == current }
        remembered.append(current)
        if remembered.count > Self.memoryLimit { memory[remembered.removeFirst()] = nil }
    }

    public func selection(for location: BrowserLocation) -> String? { memory[location]?.selection }
    public func scroll(for location: BrowserLocation) -> CGFloat? { memory[location]?.scroll }
}
