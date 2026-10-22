import AppKit

extension Chrome {
    public enum Palette {
        /// Always-dark colours for chrome drawn over photos and video, whatever the system appearance.
        public enum overMedia {
            public static let glassTint = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 29 / 255, alpha: 0.62)
            public static let glassTintLight = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 29 / 255, alpha: 0.55)
            public static let rim = NSColor(white: 1, alpha: 0.14)
            public static let separator = NSColor(white: 1, alpha: 0.18)
            public static let text = NSColor(white: 1, alpha: 0.92)
            public static let secondaryText = NSColor(white: 1, alpha: 0.7)
            public static let tertiaryText = NSColor(white: 1, alpha: 0.5)
            public static let pressed = NSColor(white: 1, alpha: 0.2)
            public static let hover = NSColor(white: 1, alpha: 0.1)
            public static let scrim = NSColor(white: 0, alpha: 0.45)
            public static let mediaShadow = NSColor(white: 0, alpha: 0.55)

            /// Forces the dark appearance on the view so system colours and glass inside it stay dark.
            @MainActor public static func apply(to view: NSView) {
                view.appearance = NSAppearance(named: .darkAqua)
            }
        }

        /// Semantic colours for chrome in ordinary windows; they follow the system appearance.
        public enum window {
            public static let label = NSColor.labelColor
            public static let secondaryLabel = NSColor.secondaryLabelColor
            public static let tertiaryLabel = NSColor.tertiaryLabelColor
            public static let separator = NSColor.separatorColor
            public static let fill = NSColor.quaternarySystemFill
            public static let background = NSColor.windowBackgroundColor
            public static let accent = NSColor.controlAccentColor
        }
    }
}
