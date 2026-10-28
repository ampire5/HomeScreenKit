import Foundation

public struct SlotTabID: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Stable display order; only a persisted snapshot rotates the selected tab to the front.
public struct SlotTabState: Equatable, Sendable {
    public private(set) var tabs: [SlotTabID]
    public private(set) var selected: SlotTabID?
    public init(tabs: [SlotTabID]) {
        var seen = Set<SlotTabID>()
        self.tabs = tabs.filter { seen.insert($0).inserted }
        selected = self.tabs.first
    }
    public mutating func select(_ id: SlotTabID) {
        if tabs.contains(id) { selected = id }
    }
    public mutating func add(_ id: SlotTabID) {
        if !tabs.contains(id) { tabs.append(id) }
        selected = id
    }
    public mutating func remove(_ id: SlotTabID) {
        guard let i = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: i)
        if selected == id { selected = tabs.isEmpty ? nil : tabs[min(i, tabs.count - 1)] }
    }
    public func snapshot() -> [SlotTabID] {
        guard let selected, let i = tabs.firstIndex(of: selected) else { return tabs }
        return Array(tabs[i...] + tabs[..<i])
    }
}

public struct SlotConfiguration: Equatable, Sendable {
    public var tabs: [SlotTabID]
    public var mode: SlotMode
    public var backdrop: SlotBackdrop
    public var autoHide: SlotAutoHide
    public var size: Int
    public var shown: Bool
    public var reveal: SlotReveal
    public init(tabs: [SlotTabID] = [], mode: SlotMode = .overlay, backdrop: SlotBackdrop = .glass,
                autoHide: SlotAutoHide = .mouseLeaves, size: Int = 400, shown: Bool = false,
                reveal: SlotReveal = .atOnce) {
        self.tabs = SlotTabState(tabs: tabs).tabs
        self.mode = mode; self.backdrop = backdrop; self.autoHide = autoHide
        self.size = size; self.shown = shown; self.reveal = reveal
    }
    public func clamped(for edge: SlotEdge) -> Self {
        var result = self
        result.size = min(max(size, edge.sizeRange.lowerBound), edge.sizeRange.upperBound)
        return result
    }
}
