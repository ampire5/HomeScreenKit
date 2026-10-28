import Foundation

/// A place at the window's edge that holds views as tabs: the playlist, plugin pages (`slot-left` / `slot-right` /
/// `slot-bottom`).
public enum SlotEdge: String, CaseIterable, Sendable, Codable {
    case left, right, bottom

    /// The config key of this slot's setting.
    public var key: String { "slot-\(rawValue)" }

    /// Points the slot may take: its width for the sides, its height for the bottom.
    public var sizeRange: ClosedRange<Int> { self == .bottom ? 120...900 : 240...1200 }
}

/// A pinned slot takes its room from the video; an overlay slot lies over the video, which keeps its size.
public enum SlotMode: String, Sendable, Codable {
    case pinned, overlay
}

/// What an overlay slot shows behind its view. Pinned slots are always dark.
public enum SlotBackdrop: String, CaseIterable, Sendable, Codable {
    case dark, glass, clear

    public var next: SlotBackdrop {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// When an overlay slot goes away by itself.
public enum SlotAutoHide: String, CaseIterable, Sendable, Codable {
    /// Once its page starts something playing (or asks to hide); also Esc, ✕ and a click on the video.
    case afterChoice = "after-choice"
    /// The pointer left the slot a moment ago, as the Dock does.
    case mouseLeaves = "mouse-leaves"
    /// Only Esc, ✕, the slot's chord or a click on the video.
    case manual
}

/// How a hidden overlay slot comes back from its edge.
public enum SlotReveal: String, CaseIterable, Sendable, Codable {
    /// The pointer touching the edge brings it.
    case atOnce = "at-once"
    /// A tongue fades in as the pointer nears the edge; a click on it brings the slot.
    case tongue
}

