import CoreGraphics

/// A card size step asked for on the home screen (⌘= / ⌘− / ⌘0, ⌘ + wheel, pinch, a mouse's side wheel).
public enum HomeResize: Equatable, Sendable {
    case larger, smaller, reset

    public static let step: CGFloat = 20

    /// The new card width from the width on screen (`fit` may have shrunk it): the next 20 pt mark up or down, within
    /// `range`. Nil for `reset`: the app's default size and layout.
    public func size(from shown: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat? {
        let s = Self.step
        let size: CGFloat
        switch self {
        case .larger: size = ((shown / s).rounded(.down) + 1) * s
        case .smaller: size = ((shown / s).rounded(.up) - 1) * s
        case .reset: return nil
        }
        return min(range.upperBound, max(range.lowerBound, size))
    }
}
