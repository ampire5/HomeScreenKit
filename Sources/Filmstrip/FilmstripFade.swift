import QuartzCore

/// The strip's fading edges: a layer whose mask fades its content out over `start` points at the leading edge and
/// `end` at the trailing one. The cells go into `layer`; the owner places it on every layout and move. Horizontal: left
/// to right; vertical: top to bottom in a flipped view's layer.
@MainActor final class FilmstripFade {
    enum Axis { case horizontal, vertical }

    let layer = CALayer()
    private let mask = CAGradientLayer()
    private let axis: Axis

    init(axis: Axis) {
        self.axis = axis
        switch axis {
        case .horizontal:
            mask.startPoint = CGPoint(x: 0, y: 0.5)
            mask.endPoint = CGPoint(x: 1, y: 0.5)
        case .vertical:
            mask.startPoint = CGPoint(x: 0.5, y: 0)
            mask.endPoint = CGPoint(x: 0.5, y: 1)
        }
        mask.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1),
                       CGColor(gray: 0, alpha: 0)]
        layer.mask = mask
    }

    /// Fills `bounds`, fading `start` and `end` points (each at most half the length along the axis).
    func place(bounds: CGRect, start: CGFloat, end: CGFloat) {
        layer.frame = bounds
        mask.frame = layer.bounds
        let length = Double(axis == .horizontal ? bounds.width : bounds.height)
        guard length > 0 else { return }
        let lead = min(0.5, Double(start) / length), trail = min(0.5, Double(end) / length)
        mask.locations = [0, NSNumber(value: lead), NSNumber(value: 1 - trail), 1]
    }
}
