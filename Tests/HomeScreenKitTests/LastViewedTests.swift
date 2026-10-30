import Foundation
import Testing
import HomeScreenModel
@testable import HomeScreenKit

@Suite struct LastViewedTests {
    @Test func fileViewTimeIsIndependentOfFolderVisitAndFileModification() {
        let viewed = Date(timeIntervalSince1970: 1234)
        let entry = BrowserEntry(url: URL(fileURLWithPath: "/Examples/cat.jpg"), name: "cat.jpg", kind: .file,
                                 lastViewedAt: viewed)
        #expect(entry.lastViewedAt == viewed)
        let card = HomeCardItem(id: entry.id, title: entry.name, tooltip: "", symbol: "photo", lastViewedAt: viewed)
        #expect(!TableColumn.visited.text(for: card).isEmpty)
        #expect(TableColumn.visited.text(for: card) == TableColumn.visited.text(for: HomeCardItem(
            id: "folder", title: "Examples", tooltip: "", symbol: "folder", summary: CardSummary(visited: viewed))))
    }
}
