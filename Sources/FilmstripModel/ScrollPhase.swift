/// The phases of a scroll event (`NSEvent.phase` / `momentumPhase`), with the same raw values, so the
/// view converts with `ScrollPhase(rawValue: event.phase.rawValue)` and this type stays AppKit-free.
public struct ScrollPhase: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let began = ScrollPhase(rawValue: 1 << 0)
    public static let stationary = ScrollPhase(rawValue: 1 << 1)
    public static let changed = ScrollPhase(rawValue: 1 << 2)
    public static let ended = ScrollPhase(rawValue: 1 << 3)
    public static let cancelled = ScrollPhase(rawValue: 1 << 4)
    public static let mayBegin = ScrollPhase(rawValue: 1 << 5)
}
