import AppKit

/// Design tokens shared by the kit and the apps built on it: radii, spacing, text styles, motion and palettes.
public enum Chrome {
    /// Corner radii.
    public enum Radius {
        public static let cell: CGFloat = 3
        public static let control: CGFloat = 6
        public static let card: CGFloat = 10
        public static let panel: CGFloat = 14
        /// The radius of a capsule of the given height.
        public static func capsule(_ height: CGFloat) -> CGFloat { height / 2 }
    }

    /// The selection ring: stroke width and the gap between it and the content.
    public enum Ring {
        public static let width: CGFloat = 2.5
        public static let gap: CGFloat = 2
    }

    /// Spacing scale.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 6
        public static let m: CGFloat = 8
        public static let l: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 20
    }

    /// Text styles mapped onto the system's dynamic text styles.
    public enum Text {
        public enum Style: CaseIterable, Sendable {
            case badge, small, label, body, title, heading, hero

            var textStyle: NSFont.TextStyle {
                switch self {
                case .badge: .caption1
                case .small: .subheadline
                case .label: .callout
                case .body: .body
                case .title: .title3
                case .heading: .title2
                case .hero: .title1
                }
            }

            var defaultWeight: NSFont.Weight? {
                switch self {
                case .badge, .title, .heading, .hero: .semibold
                case .small, .label, .body: nil
                }
            }
        }

        /// The font for a style; `weight` overrides the style's own weight.
        public static func font(_ style: Style, weight: NSFont.Weight? = nil) -> NSFont {
            let base = NSFont.preferredFont(forTextStyle: style.textStyle)
            guard let weight = weight ?? style.defaultWeight else { return base }
            return NSFont.systemFont(ofSize: base.pointSize, weight: weight)
        }

        /// The same style with monospaced digits (counters, times).
        public static func digits(_ style: Style, weight: NSFont.Weight? = nil) -> NSFont {
            let base = font(style, weight: weight)
            return NSFont.monospacedDigitSystemFont(ofSize: base.pointSize, weight: weight ?? style.defaultWeight ?? .regular)
        }
    }

    /// Animation durations; zero when the user asked to reduce motion.
    public enum Motion {
        public static let show: TimeInterval = 0.15
        public static let hide: TimeInterval = 0.25
        public static let select: TimeInterval = 0.2

        @MainActor public static func duration(
            _ d: TimeInterval,
            reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) -> TimeInterval {
            reduceMotion ? 0 : d
        }
    }

    /// A colour resolved to a `CGColor` in the view's effective appearance (dynamic colours follow light/dark).
    @MainActor public static func resolve(_ color: NSColor, in view: NSView) -> CGColor {
        var result = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }
}
