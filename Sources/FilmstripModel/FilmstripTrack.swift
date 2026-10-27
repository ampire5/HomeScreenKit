/// What `FilmstripScroll` reads of a strip's layout: where each item's centre lies on the base line and which item a
/// base position falls on. `FilmstripLayout` (Loupe's narrow cells) and `FilmstripRows` (whole pictures in rows) are
/// both tracks; the scroll moves along either the same way.
public protocol FilmstripTrack: Sendable {
    var itemCount: Int { get }
    /// The offsets the strip rests between: the first item's centre to the last's.
    var offsetRange: ClosedRange<Double> { get }
    func centre(of item: Int) -> Double
    func item(atBase position: Double) -> Int?
}
