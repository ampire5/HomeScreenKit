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
}
