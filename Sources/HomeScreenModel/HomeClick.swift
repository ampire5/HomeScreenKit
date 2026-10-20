/// Where a click on a card asks to open it.
public enum HomeClick: Equatable, Sendable {
    case open, openNewTab, openNewWindow

    /// ⇧ a new window, ⌘ or the middle button a new tab, else here. An app without tabs always opens here.
    public static func from(shift: Bool, command: Bool, middle: Bool, supportsTabs: Bool) -> HomeClick {
        guard supportsTabs else { return .open }
        if shift { return .openNewWindow }
        if command || middle { return .openNewTab }
        return .open
    }
}
