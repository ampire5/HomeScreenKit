import Foundation

/// Where the filmstrip takes the mouse, in the strip view's coordinates: `length` × `thickness` is the band,
/// `padding` its inset beside the cells on the grab side. The grab band for resizing is the band's outer `padding`,
/// just beyond the cells; the hover zone is the rest of the band. A cell's body is never the grab band, so a press
/// on a cell always opens it, and a cursor coming in from outside starts no hover before it reaches the cells.
/// `along` is the position in the strip's direction, `across` the one at right angles to it.
public struct FilmstripHitZone {
    public let length: Double
    public let thickness: Double
    public let padding: Double

    public init(length: Double, thickness: Double, padding: Double) {
        self.length = length
        self.thickness = thickness
        self.padding = padding
    }

    public func inResizeBand(along: Double, across: Double) -> Bool {
        along >= 0 && along < length && across >= thickness - padding && across < thickness
    }

    public func inHoverZone(along: Double, across: Double) -> Bool {
        along >= 0 && along < length && across >= 0 && across < thickness - padding
    }
}
