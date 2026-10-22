/// The direction the filmstrip runs in. Only `horizontal` for now; the layout names its dimensions `along` (the
/// strip's own direction) and `across` (the other one), so a vertical strip adds a case and no formula changes.
public enum FilmstripAxis: Sendable {
    case horizontal
}
