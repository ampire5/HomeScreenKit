import Foundation
import Testing
@testable import HomeScreenModel

/// The words of the mockups' cards: the poster's facts line, the dates' span, the list's Inside column and the
/// compact card's progress.
@Suite struct CardWordsTests {
    private func date(_ year: Int, _ month: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 15, hour: 12))!
    }

    @Test func posterFacts() {
        let vacation = CardSummary(photos: 248, folders: 3, insidePhotos: 412, bytes: 1_900_000_000)
        #expect(CardSummaryText.facts(vacation, pages: false) == "248 photos · 3 folders · 1.9 GB")
        #expect(CardSummaryText.facts(vacation, pages: false, withInside: true) == "248 photos · 3 folders (412) · 1.9 GB")
        var incomplete = vacation
        incomplete.insideIncomplete = true
        #expect(CardSummaryText.facts(incomplete, pages: false, withInside: true) == "248 photos · 3 folders (412+) · 1.9 GB")
        // only subfolders: the folders first, then the photos in them
        #expect(CardSummaryText.facts(CardSummary(photos: 0, folders: 14, insidePhotos: 3860), pages: false)
                == "14 folders · 3 860 photos")
        #expect(CardSummaryText.facts(CardSummary(photos: 0, folders: 1), pages: false) == "1 folder")
        // an archive of pages, or of photos
        #expect(CardSummaryText.facts(CardSummary(photos: 96, bytes: 1_200_000_000), pages: true) == "96 pages · 1.2 GB")
        #expect(CardSummaryText.facts(CardSummary(photos: 96, bytes: 1_200_000_000), pages: false) == "96 photos · 1.2 GB")
        #expect(CardSummaryText.facts(CardSummary(photos: 1), pages: false) == "1 photo")
        #expect(CardSummaryText.facts(CardSummary(photos: 1), pages: true) == "1 page")
        #expect(CardSummaryText.facts(CardSummary(), pages: false) == "")
    }

    @Test func span() {
        #expect(CardSummaryText.span(CardSummary(first: date(2024, 6), last: date(2024, 8))) == "Jun – Aug 2024")
        #expect(CardSummaryText.span(CardSummary(first: date(2023, 3), last: date(2023, 3))) == "Mar 2023")
        #expect(CardSummaryText.span(CardSummary(first: date(2009, 2), last: date(2024, 11))) == "2009–2024")   // as `years`
        #expect(CardSummaryText.span(CardSummary(last: date(2022, 5))) == "May 2022")
        #expect(CardSummaryText.span(CardSummary()) == nil)
    }

    @Test func listInside() {
        #expect(CardSummaryText.listInside(CardSummary(photos: 248, folders: 3, insidePhotos: 412), pages: false) == "248 + 412")
        #expect(CardSummaryText.listInside(CardSummary(photos: 248, folders: 3), pages: false) == "248 + 3 folders")
        #expect(CardSummaryText.listInside(CardSummary(photos: 96), pages: true) == "96 pages")
        #expect(CardSummaryText.listInside(CardSummary(photos: 0, folders: 14, insidePhotos: 3860), pages: false) == "14 folders")
        #expect(CardSummaryText.listInside(CardSummary(photos: 1120), pages: false) == "1 120")
        #expect(CardSummaryText.listInside(CardSummary(problem: .broken), pages: false) == "—")
    }

    @Test func progress() {
        #expect(CardSummaryText.progress(CardSummary(photos: 248, viewed: 0.62, seen: 153)) == "153 / 248")
        #expect(CardSummaryText.progress(CardSummary(photos: 96, viewed: 1, done: true)) == "viewed")
        #expect(CardSummaryText.progress(CardSummary(photos: 0, folders: 14)) == "not opened")
        #expect(CardSummaryText.progress(CardSummary(photos: 12)) == "not opened")
    }

    /// How long ago the folder was viewed, by calendar days in the given calendar's time zone.
    @Test func agoWords() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ month: Int, _ day: Int, _ hour: Int = 12, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let now = at(10, 23)
        #expect(CardSummaryText.ago(at(10, 23, 1), now: now, calendar: calendar) == "today")
        #expect(CardSummaryText.ago(at(10, 22, 23), now: now, calendar: calendar) == "yesterday")
        #expect(CardSummaryText.ago(at(10, 20), now: now, calendar: calendar) == "3 d ago")
        #expect(CardSummaryText.ago(at(10, 10), now: now, calendar: calendar) == "13 d ago")
        #expect(CardSummaryText.ago(at(10, 9), now: now, calendar: calendar) == "2 w ago")
        #expect(CardSummaryText.ago(at(8, 22), now: now, calendar: calendar) == "8 w ago")   // 62 days
        #expect(CardSummaryText.ago(at(8, 21), now: now, calendar: calendar) == "Aug 2026")  // 63 days: 9 weeks
        #expect(CardSummaryText.ago(at(3, 4, year: 2025), now: now, calendar: calendar) == "Mar 2025")
        // a visit dated a little ahead (another machine's clock) is today
        #expect(CardSummaryText.ago(at(10, 23, 18), now: now, calendar: calendar) == "today")
        // the days are the calendar's: 23:30 UTC on the 22nd is already the 23rd two hours east
        var east = calendar
        east.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        #expect(CardSummaryText.ago(at(10, 22, 23), now: now, calendar: east) == "today")
        #expect(CardSummaryText.ago(at(10, 22, 23), now: now, calendar: calendar) == "yesterday")
    }

    /// A compact card's row 4: the progress, then how long ago.
    @Test func progressLine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
        let visited = now.addingTimeInterval(-3 * 86_400)
        func line(_ s: CardSummary) -> String? { CardSummaryText.progressLine(s, now: now, calendar: calendar) }
        #expect(line(CardSummary(photos: 248, viewed: 0.62, seen: 153, visited: visited)) == "153 / 248 · 3 d ago")
        #expect(line(CardSummary(photos: 96, viewed: 1, visited: visited, done: true)) == "viewed · 3 d ago")
        #expect(line(CardSummary(photos: 12)) == "not opened")
        #expect(line(CardSummary(photos: 248, viewed: 0.62, seen: 153)) == "153 / 248")   // the date not known yet
        #expect(line(CardSummary(photos: 0, viewed: 0.5, visited: visited)) == nil)        // nothing to count
    }
}
