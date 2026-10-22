import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct CardSummaryTextTests {
    private func date(_ year: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 6, day: 15, hour: 12))!
    }

    @Test func insideLine() {
        #expect(CardSummaryText.inside(CardSummary(photos: 248, folders: 3)) == "248 · 3 folders")
        #expect(CardSummaryText.inside(CardSummary(photos: 248, folders: 1)) == "248 · 1 folder")
        #expect(CardSummaryText.inside(CardSummary(photos: 248)) == "248")
        #expect(CardSummaryText.inside(CardSummary(photos: 248, folders: 0)) == "248")
        #expect(CardSummaryText.inside(CardSummary(folders: 3, insidePhotos: 1204)) == "+1 204 inside")
        #expect(CardSummaryText.inside(CardSummary(folders: 3, insidePhotos: 1204, insideIncomplete: true)) == "+1 204+ inside")
        #expect(CardSummaryText.inside(CardSummary(photos: 248, folders: 3, insidePhotos: 1204)) == "248 · +1 204 inside")
        #expect(CardSummaryText.inside(CardSummary(photos: 1_204_000)) == "1 204 000")
    }

    @Test func yearsSpan() {
        #expect(CardSummaryText.years(CardSummary(first: date(2019), last: date(2023))) == "2019–2023")
        #expect(CardSummaryText.years(CardSummary(first: date(2021), last: date(2021))) == "2021")
        #expect(CardSummaryText.years(CardSummary(first: date(2021))) == "2021")
        #expect(CardSummaryText.years(CardSummary(last: date(2022))) == "2022")
        #expect(CardSummaryText.years(CardSummary()) == nil)
    }

    @Test func sizeText() {
        #expect(CardSummaryText.size(CardSummary(bytes: 4_200_000_000)) == "4.2 GB")
        #expect(CardSummaryText.size(CardSummary(bytes: 50_000_000)) == "50 MB")
        #expect(CardSummaryText.size(CardSummary(bytes: 999_960_000)) == "1.0 GB")
        #expect(CardSummaryText.size(CardSummary(bytes: 999_400_000)) == "999 MB")
        #expect(CardSummaryText.size(CardSummary(bytes: 1_500)) == "1.5 KB")
        #expect(CardSummaryText.size(CardSummary(bytes: 0)) == nil)
        #expect(CardSummaryText.size(CardSummary()) == nil)
    }

    @Test func viewedText() {
        #expect(CardSummaryText.viewed(CardSummary(photos: 248, viewed: 137.0 / 248)) == "137 / 248")
        #expect(CardSummaryText.viewed(CardSummary(photos: 248)) == nil)
        #expect(CardSummaryText.viewed(CardSummary(photos: 0, viewed: 0.5)) == nil)
    }
}
