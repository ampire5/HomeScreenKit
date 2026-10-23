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

    /// `137 / 248`: the photos seen (`seen`, else `viewed` of the photos now) of the photos now; nil when nothing is
    /// known or the folder is empty.
    public static func viewed(_ s: CardSummary) -> String? {
        guard let fraction = s.viewed, let photos = s.photos, photos > 0 else { return nil }
        let seen = min(photos, max(0, s.seen ?? Int((fraction * Double(photos)).rounded())))
        return "\(grouped(seen)) / \(grouped(photos))"
    }

    // MARK: The mockups' words

    /// `248 photos`, `1 photo`, `96 pages`, `3 folders`.
    public static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(grouped(n)) \(noun)s"
    }

    /// A poster's facts line: `248 photos · 3 folders · 1.9 GB`; a folder of folders only `14 folders · 3 860 photos`
    /// (the photos in them, as far as known); an archive of pages `96 pages · 1.2 GB`. `withInside` adds the
    /// subfolders' photos after their count, `3 folders (412)` (a `+` while some are unknown). Empty when nothing
    /// is known.
    public static func facts(_ s: CardSummary, pages: Bool, withInside: Bool = false) -> String {
        var parts: [String] = []
        let photos = s.photos ?? 0, folders = s.folders ?? 0
        let inside = s.insidePhotos.map { grouped($0) + (s.insideIncomplete ? "+" : "") }
        if photos > 0 {
            parts.append(count(photos, pages ? "page" : "photo"))
            if folders > 0 {
                parts.append(count(folders, "folder") + (withInside ? inside.map { " (\($0))" } ?? "" : ""))
            }
        } else if folders > 0 {
            parts.append(count(folders, "folder"))
            if let n = s.insidePhotos, let inside { parts.append(inside + (n == 1 && !s.insideIncomplete ? " photo" : " photos")) }
        }
        if let size = size(s) { parts.append(size) }
        return parts.joined(separator: " · ")
    }

    /// The dates' span in months: `Jun – Aug 2024`, `Mar 2023` (one month), `2009–2024` (over years: the same
    /// year range as `years`); nil without a date. Month names are English, like the rest of the interface; local calendar and time zone.
    public static func span(_ s: CardSummary) -> String? {
        let dates = [s.first, s.last].compactMap { $0 }
        guard let low = dates.min(), let high = dates.max() else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let a = calendar.dateComponents([.year, .month], from: low), b = calendar.dateComponents([.year, .month], from: high)
        guard let y1 = a.year, let y2 = b.year, let m1 = a.month, let m2 = b.month else { return nil }
        if y1 != y2 { return "\(y1)–\(y2)" }
        if m1 == m2 { return "\(months[m1 - 1]) \(y1)" }
        return "\(months[m1 - 1]) – \(months[m2 - 1]) \(y1)"
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The list's Inside column: `248 + 412` (own and the subfolders' photos), `248 + 3 folders` while those are
    /// unknown, `14 folders` (folders only), `1 120` or `96 pages`; `—` when nothing is known.
    public static func listInside(_ s: CardSummary, pages: Bool) -> String {
        let photos = s.photos ?? 0, folders = s.folders ?? 0
        if photos > 0 {
            if folders > 0 {
                if let inside = s.insidePhotos { return "\(grouped(photos)) + \(grouped(inside))\(s.insideIncomplete ? "+" : "")" }
                return "\(grouped(photos)) + \(count(folders, "folder"))"
            }
            return pages ? count(photos, "page") : grouped(photos)
        }
        if folders > 0 { return count(folders, "folder") }
        return s.photos == nil ? "—" : "0"
    }

    /// A compact card's progress text: `153 / 248`, `viewed` (to the end), `not opened` (no visit).
    public static func progress(_ s: CardSummary) -> String? {
        if s.done { return "viewed" }
        if s.viewed == nil { return "not opened" }
        return viewed(s)
    }

    /// How long ago `date` was, by calendar days in `calendar`'s time zone: `today`, `yesterday`, `3 d ago` (2…13
    /// days), `2 w ago` (2…8 weeks), then the month, `Mar 2025` (English month names, as with `en_US_POSIX`). A date
    /// ahead of `now` (another machine's clock) is `today`.
    public static func ago(_ date: Date, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        case 2...13: return "\(days) d ago"
        case 14...62: return "\(days / 7) w ago"
        default:
            let c = calendar.dateComponents([.year, .month], from: date)
            guard let year = c.year, let month = c.month else { return "" }
            return "\(months[month - 1]) \(year)"
        }
    }

    /// A compact card's row 4: the progress and how long ago it was viewed, `153 / 248 · 3 d ago`, `viewed · 3 d ago`;
    /// `not opened` (no visit); nil when there is nothing to count.
    public static func progressLine(_ s: CardSummary, now: Date,
                                    calendar: Calendar = Calendar(identifier: .gregorian)) -> String? {
        guard let progress = progress(s) else { return nil }
        guard s.viewed != nil || s.done, let visited = s.visited else { return progress }
        return progress + " · " + ago(visited, now: now, calendar: calendar)
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
