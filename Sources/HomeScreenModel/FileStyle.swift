import CoreGraphics

/// How the browser shows a listing's files: what they are called in the counts, the shape of their slot (its width
/// over the picture's height), and whether a card carries the entry's own line (`BrowserEntry.subtitle`) and progress
/// on its picture, as video apps put the length and how far it was watched. Photos unless the app says otherwise.
public struct FileStyle: Equatable, Sendable {
    public enum MediaKind: Sendable { case photo, video }
    /// Semantic capabilities, independent of the app's displayed noun.
    public var mediaKind: MediaKind
    public var noun: String
    public var aspect: CGFloat
    public var facts: Bool
    /// A line of the file's facts (`FileFacts`: a video's stream and size, a photo's exposure) under its name, when
    /// names are under the pictures (file-cards spec §2).
    public var factsLine: Bool

    public init(noun: String, aspect: CGFloat, facts: Bool, factsLine: Bool = false, mediaKind: MediaKind = .photo) {
        self.mediaKind = mediaKind
        self.noun = noun
        self.aspect = aspect
        self.facts = facts
        self.factsLine = factsLine
    }

    public static let photos = FileStyle(noun: "photo", aspect: 1, facts: false)
    public static let videos = FileStyle(noun: "video", aspect: 16.0 / 9, facts: true, factsLine: true, mediaKind: .video)

    /// `Photos`, `Videos`: the heading over a folder's files.
    public var heading: String { noun.prefix(1).uppercased() + noun.dropFirst() + "s" }
}
