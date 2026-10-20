import Foundation

/// Recent's sections when it is ordered by date: Today, Yesterday, This Week, Earlier. The entries come already
/// ordered (newest or oldest first), so each title is one run of them and the sections keep the entries' order.
public enum DateGroups {
    /// One section per run of equal titles; a missing date is Earlier.
    public static func sections(_ dates: [Date?], now: Date, calendar: Calendar) -> [(title: String, count: Int)] {
        var out: [(title: String, count: Int)] = []
        for date in dates {
            let title = self.title(date, now: now, calendar: calendar)
            if out.last?.title == title { out[out.count - 1].count += 1 } else { out.append((title, 1)) }
        }
        return out
    }

    static func title(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return "Earlier" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if date < now, calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return "This Week" }
        return "Earlier"
    }
}
