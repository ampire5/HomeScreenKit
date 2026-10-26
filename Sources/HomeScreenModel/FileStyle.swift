import CoreGraphics

/// How the browser shows a listing's files: what they are called in the counts, the shape of their slot (its width
/// over the picture's height), and whether a card carries the entry's own line (`BrowserEntry.subtitle`) and progress
/// on its picture, as video apps put the length and how far it was watched. Photos unless the app says otherwise.
public struct FileStyle: Equatable, Sendable {
    public var noun: String
    public var aspect: CGFloat
    public var facts: Bool

    public init(noun: String, aspect: CGFloat, facts: Bool) {
        self.noun = noun
        self.aspect = aspect
        self.facts = facts
    }

    public static let photos = FileStyle(noun: "photo", aspect: 1, facts: false)
    public static let videos = FileStyle(noun: "video", aspect: 16.0 / 9, facts: true)

    /// `Photos`, `Videos`: the heading over a folder's files.
    public var heading: String { noun.prefix(1).uppercased() + noun.dropFirst() + "s" }
}
