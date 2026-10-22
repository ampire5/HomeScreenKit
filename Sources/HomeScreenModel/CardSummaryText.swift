import Foundation

/// The words of a card's facts, in English like the rest of the interface. The same on every machine: the grouping is
/// a space, whatever the locale.
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

    /// `2019–2023`, or `2021` when both dates are in one year; nil without a date.
    public static func years(_ s: CardSummary) -> String? {
        let calendar = Calendar(identifier: .gregorian)
        let years = [s.first, s.last].compactMap { $0 }.map { calendar.component(.year, from: $0) }
        guard let low = years.min(), let high = years.max() else { return nil }
        return low == high ? "\(low)" : "\(low)–\(high)"
    }

    /// `4.2 GB`, `50 MB`: 1024-based units like the Finder's older sizes; nil when unknown or empty.
    public static func size(_ s: CardSummary) -> String? {
        guard let bytes = s.bytes, bytes > 0 else { return nil }
        let value = Double(bytes)
        let units: [(String, Double)] = [("GB", 1_073_741_824), ("MB", 1_048_576), ("KB", 1024)]
        for (name, unit) in units where value >= unit {
            let n = value / unit
            return n < 10 ? String(format: "%.1f %@", n, name) : String(format: "%.0f %@", n, name)
        }
        return "\(bytes) B"
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
