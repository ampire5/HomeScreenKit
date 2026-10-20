import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct DateGroupsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Monday 2026-10-20 15:00 is "now"; Sunday the 18th is in the week before (weeks start on Monday).
    private var now: Date { date(2026, 10, 20, 15) }

    @Test func groupsNewestFirst() {
        let dates: [Date?] = [date(2026, 10, 20, 10), date(2026, 10, 19, 9), date(2026, 10, 18, 12),
                              date(2026, 9, 1, 12), nil]
        let sections = DateGroups.sections(dates, now: now, calendar: calendar)
        let sundayInWeek = calendar.isDate(date(2026, 10, 18, 12), equalTo: now, toGranularity: .weekOfYear)
        let expected = sundayInWeek ? ["Today", "Yesterday", "This Week", "Earlier"] : ["Today", "Yesterday", "Earlier"]
        #expect(sections.map(\.title) == expected)
        #expect(sections.map(\.count).reduce(0, +) == 5)
        #expect(sections.first?.count == 1)
    }

    @Test func thisWeekBetweenYesterdayAndEarlier() {
        // Thursday 2026-10-22: Monday the 20th is this week, not today or yesterday.
        let thursday = date(2026, 10, 22, 15)
        let dates: [Date?] = [date(2026, 10, 22, 8), date(2026, 10, 21, 8), date(2026, 10, 20, 8), date(2026, 10, 1, 8)]
        let sections = DateGroups.sections(dates, now: thursday, calendar: calendar)
        #expect(sections.map(\.title) == ["Today", "Yesterday", "This Week", "Earlier"])
        #expect(sections.map(\.count) == [1, 1, 1, 1])
    }

    @Test func groupsOldestFirst() {
        let dates: [Date?] = [nil, date(2026, 9, 1, 12), date(2026, 10, 19, 9), date(2026, 10, 20, 10), date(2026, 10, 20, 11)]
        let sections = DateGroups.sections(dates, now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["Earlier", "Yesterday", "Today"])
        #expect(sections.map(\.count) == [2, 1, 2])
    }

    @Test func emptyGivesNone() {
        #expect(DateGroups.sections([], now: now, calendar: calendar).isEmpty)
    }
}
