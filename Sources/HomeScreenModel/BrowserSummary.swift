import Foundation

/// The browser's words about a listing: the footer under the grid and the subtitle under the path.
public enum BrowserSummary {
    /// `N photos · M folders · 1.8 GB` (parts that are zero left out; the size only once the listing is complete), and
    /// a state: still listing a slow share, or how much a filter leaves. A source's `noun` counts what is not a file
    /// (`3 sessions`) in place of folders; `fileNoun` names the files (`FileStyle.noun`).
    public static func footer(entries: [BrowserEntry], filtered: Int?, complete: Bool,
                              more: Bool, noun: String? = nil, fileNoun: String = "photo") -> (line: String, state: String?) {
        var photos = 0, folders = 0, bytes: Int64 = 0
        for e in entries {
            if e.isFile { photos += 1; bytes += e.size ?? 0 } else { folders += 1 }
        }
        var parts: [String] = []
        if photos > 0 { parts.append(count(photos, fileNoun)) }
        if folders > 0 { parts.append(count(folders, noun ?? "folder")) }
        if complete, bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        let state: String?
        if more {
            state = "Listing is slow — \(number(entries.count)) so far"
        } else if let filtered {
            state = "Filter: \(number(filtered)) of \(number(entries.count))"
        } else {
            state = nil
        }
        return (parts.joined(separator: " · "), state)
    }

    /// While listing, how many names have come; else the selected card's name, size and date; else the footer line.
    public static func subtitle(selected: BrowserEntry?, entries: [BrowserEntry], loading: Int?,
                                fileNoun: String = "photo") -> String {
        if let loading { return "Loading… \(number(loading))" }
        guard let selected else {
            return footer(entries: entries, filtered: nil, complete: true, more: false, fileNoun: fileNoun).line
        }
        var parts = [selected.name]
        if let size = selected.size, !selected.isContainer {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let date = selected.date { parts.append(dateFormat.string(from: date)) }
        return parts.joined(separator: " · ")
    }

    /// Stable details for the selected card, shown in the browser's fixed bottom status area.
    public static func selection(_ entry: BrowserEntry?, fileNoun: String = "photo") -> String {
        guard let entry else { return "" }
        if entry.isFile { return subtitle(selected: entry, entries: [], loading: nil) }

        var parts = [entry.name]
        if let summary = entry.summary {
            if let photos = summary.photos { parts.append(count(photos, fileNoun)) }
            if let folders = summary.folders { parts.append(count(folders, "folder")) }
            if let bytes = summary.bytes, bytes > 0 {
                parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
            if let first = summary.first, let last = summary.last, first != last {
                parts.append("\(dateFormat.string(from: first))–\(dateFormat.string(from: last))")
            } else if let date = summary.last ?? summary.first ?? entry.date {
                parts.append(dateFormat.string(from: date))
            }
        } else if let subtitle = entry.subtitle {
            parts.append(subtitle)
            if let date = entry.date { parts.append(dateFormat.string(from: date)) }
        } else {
            if let photos = entry.count { parts.append(count(photos, fileNoun)) }
            if let date = entry.date { parts.append(dateFormat.string(from: date)) }
        }
        return parts.joined(separator: " · ")
    }

    /// `2 719`: grouped as the user's locale groups.
    public static func number(_ n: Int) -> String {
        numberFormat.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(number(n)) \(noun)s"
    }

    private static let numberFormat: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    /// `18 Oct 2026`: English, as the rest of the browser's words.
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}
