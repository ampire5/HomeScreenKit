import Foundation

/// The toolbar's kind capsule: everything, the folders and archives, or the photos.
public enum BrowserKindFilter: String, CaseIterable, Sendable {
    case all, folders, photos

    public var title: String {
        switch self {
        case .all: "All"
        case .folders: "Folders"
        case .photos: "Photos"
        }
    }
}

/// What the browser shows of a listing: a kind and a piece of the name. The name matches ignoring case and accents,
/// whichever Unicode form the file system gave it (a share may hand out decomposed names); the order is kept.
public struct BrowserFilter: Equatable, Sendable {
    public var kind: BrowserKindFilter
    public var text: String

    public init(kind: BrowserKindFilter = .all, text: String = "") {
        self.kind = kind
        self.text = text
    }

    private var needle: String { text.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping }

    public var isActive: Bool { kind != .all || !needle.isEmpty }

    public func apply(_ entries: [BrowserEntry]) -> [BrowserEntry] {
        let needle = needle
        return entries.filter { e in
            switch kind {
            case .all: break
            case .folders: guard e.isContainer else { return false }
            case .photos: guard !e.isContainer else { return false }
            }
            guard !needle.isEmpty else { return true }
            return e.name.precomposedStringWithCanonicalMapping
                .range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
