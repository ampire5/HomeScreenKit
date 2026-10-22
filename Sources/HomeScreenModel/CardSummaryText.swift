import Foundation

/// The words of a card's facts, in English like the rest of the interface. Numbers are grouped with a space whatever
/// the locale; years are in the local calendar and time zone, like the Finder's dates.
public enum CardSummaryText {
    /// `248 · 3 folders`; `248`; `+1 204 inside` (the subfolders' photos, `+1 204+ inside` while some are unknown),
    /// after the card's own photos when it has any.
    public static func inside(_ s: CardSummary) -> String {
        var parts: [String] = []
        if let photos = s.photos, photos > 0 || (s.insidePhotos == nil && (s.folders ?? 0) == 0) {
            parts.append(grouped(photos))
        }
        if let inside = s.insidePhotos {
            parts.append("+\(grouped(inside))\(s.insideIncomplete ? "+" : "") inside")
        } else if let folders = s.folders, folders > 0 {
            parts.append(folders == 1 ? "1 folder" : "\(grouped(folders)) folders")
        }
        return parts.joined(separator: " · ")
    }

    /// `2019–2023` (local time zone), or `2021` when both dates are in one year; nil without a date.
    public static func years(_ s: CardSummary) -> String? {
        let calendar = Calendar(identifier: .gregorian)
        let years = [s.first, s.last].compactMap { $0 }.map { calendar.component(.year, from: $0) }
        guard let low = years.min(), let high = years.max() else { return nil }
        return low == high ? "\(low)" : "\(low)–\(high)"
    }

    /// `4.2 GB`, `50 MB`: decimal units like the Finder (1 GB = 10^9 bytes); nil when unknown or empty. A value that
    /// rounds to 1000 of a unit is shown in the next one (`1.0 GB`, not `1000 MB`).
    public static func size(_ s: CardSummary) -> String? {
        guard let bytes = s.bytes, bytes > 0 else { return nil }
        let units: [(name: String, size: Double)] = [("KB", 1e3), ("MB", 1e6), ("GB", 1e9), ("TB", 1e12)]
        let value = Double(bytes)
        guard value >= 1e3 else { return "\(bytes) B" }
        var i = units.lastIndex { value >= $0.size } ?? 0
        while true {
            let n = value / units[i].size
            let rounded = n < 10 ? (n * 10).rounded() / 10 : n.rounded()
            if rounded >= 1000, i + 1 < units.count { i += 1; continue }
            return (n < 10 ? String(format: "%.1f", rounded) : String(format: "%.0f", rounded)) + " " + units[i].name
        }
    }

    /// `137 / 248`: the photos seen of all; nil when nothing is known or the folder is empty.
    public static func viewed(_ s: CardSummary) -> String? {
        guard let fraction = s.viewed, let photos = s.photos, photos > 0 else { return nil }
        let seen = min(photos, max(0, Int((fraction * Double(photos)).rounded())))
        return "\(grouped(seen)) / \(grouped(photos))"
    }

    /// `1 204`.
    private static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = "", count = 0
        for ch in digits.reversed() {
            if count > 0, count % 3 == 0 { out.append(" ") }
            out.append(ch)
            count += 1
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}
