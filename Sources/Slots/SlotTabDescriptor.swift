import AppKit
import SlotModel
import SlotChrome

/// A live tab's app-owned behavior. Instances survive hide and tab switches.
@MainActor public final class SlotPage {
    public let view: NSView
    public var tools: () -> [SlotTool] = { [] }
    public var focus: () -> Void = {}
    public var isTyping: () -> Bool = { false }
    public var cancelInteraction: () -> Void = {}
    public var drawsOwnTextShadow = false
    public var reload: (() -> Void)?
    public var filterEdited: (String) -> Void = { _ in }
    public var filterCommand: (Selector) -> Bool = { _ in false }
    public var filterClosed: () -> Void = {}
    public var filterEnded: () -> Void = {}
    public var visibilityChanged: (Bool) -> Void
    public var dropped: () -> Void
    public init(view: NSView, visibilityChanged: @escaping (Bool) -> Void = { _ in }, dropped: @escaping () -> Void = {}) {
        self.view = view; self.visibilityChanged = visibilityChanged; self.dropped = dropped
    }
}

@MainActor public struct SlotTabDescriptor {
    public let id: SlotTabID
    public let title: String
    public let symbol: String?
    public let singleton: Bool
    public let makePage: (SlotEdge) -> SlotPage?
    public init(id: SlotTabID, title: String, symbol: String? = nil, singleton: Bool = false,
                makePage: @escaping (SlotEdge) -> SlotPage?) {
        self.id = id; self.title = title; self.symbol = symbol; self.singleton = singleton; self.makePage = makePage
    }
}
