import CoreGraphics

/// A card size change asked for on the home screen: `larger`/`smaller` one column (⌘ + wheel, pinch, a mouse's side
/// wheel), `largerSize`/`smallerSize` the next of `sizes` (⌘= / ⌘−, the toolbar's − and +), `to` a size (the toolbar's
/// slider), `reset` the app's default (⌘0).
public enum HomeResize: Equatable, Sendable {
    case larger, smaller, largerSize, smallerSize, reset
    case to(CGFloat)

    public static let step: CGFloat = 20
    /// Small, Medium, Large, Huge: each step a change seen at once, where a column of twelve is not.
    public static let sizes: [CGFloat] = [100, 160, 240, 360]

    /// The size after `shown` among `sizes`: the next one past it (5 % either way, so a size just set is not taken
    /// again), or `shown` itself past the last.
    public static func nextSize(after shown: CGFloat, larger: Bool) -> CGFloat {
        larger ? sizes.first { $0 > shown * 1.05 } ?? max(shown, sizes.last!)
               : sizes.last { $0 < shown * 0.95 } ?? min(shown, sizes.first!)
    }

    /// The new card width from the width on screen (`fit` may have shrunk it): the next 20 pt mark up or down, within
    /// `range`. Nil for `reset`: the app's default size and layout.
    public func size(from shown: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat? {
        let s = Self.step
        let size: CGFloat
        switch self {
        case .larger: size = ((shown / s).rounded(.down) + 1) * s
        case .smaller: size = ((shown / s).rounded(.up) - 1) * s
        case .largerSize, .smallerSize: size = Self.nextSize(after: shown, larger: self == .largerSize)
        case .to(let wanted): size = wanted
        case .reset: return nil
        }
        return min(range.upperBound, max(range.lowerBound, size))
    }
}
