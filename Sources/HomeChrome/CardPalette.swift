import AppKit

extension Chrome.Palette {
    /// The colours of Home's folder and archive cards (posters, compact cards, the list), from the approved mockups
    /// (light / dark). The card sits on the window's own background, which is not repainted.
    public enum card {
        /// The card's plate: the band under a poster's cover, a compact card, the list's container.
        public static let background = dynamic(light: 0xFFFFFF, dark: 0x232326)
        public static let label = dynamic(light: 0x1D1D1F, dark: 0xEDEDEF)
        public static let secondary = dynamic(light: 0x5A5A60, dark: 0xA8A8AE)
        /// The ring round a card, the list's separators, the border of a text chip (RTL).
        public static let separator = dynamic(light: (0x000000, 0.08), dark: (0xFFFFFF, 0.09))
        /// Pointer feedback on a card plate in either appearance.
        public static let hoverBorder = dynamic(light: (0x000000, 0.25), dark: (0xFFFFFF, 0.28))
        /// A progress track under its fill.
        public static let track = dynamic(light: (0x000000, 0.09), dark: (0xFFFFFF, 0.14))
        /// The bars of the dates' histogram.
        public static let spark = dynamic(light: 0x8E8E94, dark: 0x8C8C94)
        /// An unavailable folder's or a damaged archive's line and glyph.
        public static let warning = dynamic(light: 0xA4520B, dark: 0xFFB25C)
        /// Match the system selection accent and resolve it in the drawing appearance.
        public static let accent = NSColor.controlAccentColor
        /// A new-item count sits on the same plate as the name.
        public static let pill = NSColor.clear
        public static let pillText = secondary
        /// A label over the cover (ZIP): white on a dark veil, whatever the window.
        public static let coverChip = NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 20 / 255, alpha: 0.58)
        public static let coverChipText = NSColor.white

        /// Subtle steps above the card plate while the cover and facts are pending.
        public static let waitingCover = dynamic(light: 0xE4E4E0, dark: 0x303033)
        public static let waitingLine = dynamic(light: 0xECECE8, dark: 0x2D2D30)
        public static let shimmer = dynamic(light: (0xFFFFFF, 0.32), dark: (0xF2F2F4, 0.06))
        /// Still placeholders stay legible without the passing highlight.
        public static let waitingCoverStill = dynamic(light: 0xECECE9, dark: 0x343438)
        public static let waitingLineStill = dynamic(light: 0xF2F2EF, dark: 0x303034)

        static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }

        static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
            dynamic(light: (light, 1), dark: (dark, 1))
        }

        static func dynamic(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> NSColor {
            let l = rgb(light.0, light.1), d = rgb(dark.0, dark.1)
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? d : l
            }
        }
    }
}
