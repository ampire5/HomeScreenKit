import AppKit

extension Chrome.Palette {
    /// The thumbnails' progress pill and its popover (the progress board, «Пилюля в тулбаре», «По щелчку»). The ring's
    /// fill and track and the popover's bars use `card.accent` and `card.track`.
    public enum progress {
        /// The paused ring: the board's #8E8E94, the same grey in both appearances.
        public static let pausedRing = card.dynamic(light: 0x8E8E94, dark: 0x8E8E94)
        /// The pill's inset highlight along its top edge (`inset 0 0.5px 0 rgba(255,255,255,.35)`), the board's in both.
        public static let highlight = card.dynamic(light: (0xFFFFFF, 0.35), dark: (0xFFFFFF, 0.35))
        /// The popover buttons' 0.5 pt border: the board's black .2; dark (not on the board), white .2.
        public static let buttonBorder = card.dynamic(light: (0x000000, 0.2), dark: (0xFFFFFF, 0.2))
    }
}
