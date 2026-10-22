import Foundation

/// The strip's thickness for a drag of its grab band, as a pure function of how far the cursor has moved since the
/// press: the band's edge follows the cursor 1:1, so back to the press point is back to the start thickness. Past
/// the thickness range it goes on; the caller clamps it.
public struct FilmstripResizeDrag {
    public let startThickness: Double

    public init(startThickness: Double) {
        self.startThickness = startThickness
    }

    /// The thickness for the cursor `delta` points towards the cells' side of the band (negative: away).
    public func thickness(forDrag delta: Double) -> Double { startThickness + delta }
}
