import Foundation

/// Typing a name's first letters selects it, as in Finder: the letters add up while each follows the last within a
/// second. Names compare composed (an SMB share often hands them over decomposed) and without case; accents count.
public struct BrowserTypeSelect: Sendable {
    private var buffer = ""
    private var last: TimeInterval = -.infinity

    public init() {}

    /// The letters typed so far, `text` included.
    public mutating func type(_ text: String, at time: TimeInterval) -> String {
        if time - last > 1 { buffer = "" }
        buffer += text
        last = time
        return buffer
    }

    /// A name is being typed at `time`: a letter came within the last second, so the next one adds to it (an app's
    /// single-letter shortcut gives way to it then, as F does in Finder's type-to-select).
    public func isTyping(at time: TimeInterval) -> Bool { !buffer.isEmpty && time - last <= 1 }

    /// The first name from `start` on (wrapping round) that begins with `prefix`.
    public static func match(_ prefix: String, in names: [String], from start: Int) -> Int? {
        guard !names.isEmpty else { return nil }
        let wanted = fold(prefix)
        let first = min(max(0, start), names.count - 1)
        for step in 0..<names.count {
            let i = (first + step) % names.count
            if fold(names[i]).hasPrefix(wanted) { return i }
        }
        return nil
    }

    private static func fold(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }
}
