import Foundation

/// The File View tabs a host can save between launches. A nil folder represents Places.
public struct FileTabSession: Codable, Equatable, Sendable {
    public struct Tab: Codable, Equatable, Sendable {
        public let id: UUID
        public let folder: URL?
        public let selection: String?
        public let anchor: BrowserAnchor?

        public init(id: UUID, folder: URL?, selection: String?, anchor: BrowserAnchor?) {
            self.id = id
            self.folder = folder
            self.selection = selection
            self.anchor = anchor
        }
    }

    public let version: Int
    public let tabs: [Tab]
    public let selectedID: UUID

    public init(tabs: [Tab], selectedID: UUID) {
        version = 1
        self.tabs = tabs
        self.selectedID = selectedID
    }

    package var isValid: Bool {
        let ids = Set(tabs.map(\.id))
        return ids.count == tabs.count && ids.contains(selectedID) && tabs.allSatisfy { $0.folder?.isFileURL ?? true }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Unsupported File View session version")
        }
        tabs = try container.decode([Tab].self, forKey: .tabs)
        selectedID = try container.decode(UUID.self, forKey: .selectedID)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .tabs, in: container,
                                                   debugDescription: "Invalid File View tab set")
        }
    }
}
