import AppKit

extension Chrome.Palette {
    /// The colours of Home's folder and archive cards (posters, compact cards, the list), from the approved mockups
    /// (light / dark). The card sits on the window's own background, which is not repainted.
    public enum card {
        /// The card's plate: the band under a poster's cover, a compact card, the list's container.
        public static let background = dynamic(light: 0xFFFFFF, dark: 0x2C2C2F)
        public static let label = dynamic(light: 0x1D1D1F, dark: 0xF2F2F4)
        public static let secondary = dynamic(light: 0x5F5F64, dark: 0xA9A9B0)
        /// The ring round a card, the list's separators, the border of a text chip (RTL).
        public static let separator = dynamic(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.12))
        /// A progress track under its fill.
        public static let track = dynamic(light: (0x000000, 0.09), dark: (0xFFFFFF, 0.14))
        /// The bars of the dates' histogram.
        public static let spark = dynamic(light: 0x8E8E94, dark: 0x8C8C94)
        /// An unavailable folder's or a damaged archive's line and glyph.
        public static let warning = dynamic(light: 0xA4520B, dark: 0xFFB25C)
        /// The progress fill: the same blue in both appearances.
        public static let accent = rgb(0x0A84FF)
        /// The `+N` pill and its text.
        public static let pill = rgb(0x0A6CD6)
        public static let pillText = NSColor.white
        /// A label over the cover (ZIP): white on a dark veil, whatever the window.
        public static let coverChip = NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 20 / 255, alpha: 0.58)
        public static let coverChipText = NSColor.white

        /// A waiting card (the progress board, «Карточки в ожидании»): its cover placeholder and its two lines, and
        /// the highlight sweeping over them. Light: the board's #E4E4E0, #ECECE8 and white .55. Dark (not drawn on the
        /// board): the same step from the plate — `label` over `background` at .12 and .084, as #E4E4E0 and #ECECE8 are
        /// over white — and a light glint of `label` at .09, lifting the placeholder as much as the light one does.
        public static let waitingCover = dynamic(light: 0xE4E4E0, dark: 0x444447)
        public static let waitingLine = dynamic(light: 0xECECE8, dark: 0x3D3D40)
        public static let shimmer = dynamic(light: (0xFFFFFF, 0.55), dark: (0xF2F2F4, 0.09))

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
